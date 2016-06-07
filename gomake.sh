#!/bin/bash
# this is a script to build go apps
set -e

echo_red() {
    echo >&2 -e "\033[0;31m${@}\033[0m"
}

echo_purple() {
    echo -e "\033[0;35m${@}\033[0m"
}

echo_green() {
    echo -e "\033[0;32m${@}\033[0m"
}

gomake_update() {
    wget https://raw.githubusercontent.com/n0rad/gomake/master/gomake.sh -o ${dir}/gomake.tmp
    chmod +x ${dir}/gomake.tmp
    mv ${dir}/gomake.tmp ${dir}/$0
}

clean() {
    echo_green "Cleaning"
    rm -Rf ${dir}/${target_name}
}

build() {
    start=`date +%s`

    [ -z "$1" ] || osarchi="$1"
    [ ! -z ${version+x} ] || version="0"

    [ -f ${GOPATH}/bin/godep ] || go get github.com/tools/godep
    [ -f /usr/bin/upx ] || (echo "upx is required to build" && exit 1)

    echo_green "Save Dependencies"
    godep save ./${dir}/... || echo "Cannot save dependencies. Continuing"

    IFS=',' read -ra current <<< "$osarchi"
    for e in "${current[@]}"; do
        echo_green "Building $e"

        GOOS="${e%-*}" GOARCH="${e#*-}" \
        godep go build -ldflags "-X main.BuildTime=`date -u '+%Y-%m-%d_%H:%M:%S_UTC'` -X main.Version=${version}-`git rev-parse HEAD`" \
            -o ${dir}/${target_name}/${app}-v${version}-${e}/${app}

        if [ "${e%-*}" != "darwin" ]; then
            echo_green "Compressing ${e}"
            upx ${dir}/${target_name}/${app}-v${version}-${e}/${app} &> /dev/null
        fi

        if [ "${e%-*}" == "windows" ]; then
            mv ${dir}/${target_name}/${app}-v${version}-${e}/${app} ${dir}/${target_name}/${app}-v${version}-${e}/${app}.exe
        fi
    done
    echo_purple "Build duration : $((`date +%s`-${start}))s"
}


install() {
    echo_green "Installing"
    cp ${dir}/${target_name}/${app}-v${version}-$(go env GOHOSTOS)-$(go env GOHOSTARCH)/${app}* ${GOPATH}/bin/
}

quality() {
    start=`date +%s`

    go_files=`find . -name '*.go' 2> /dev/null | grep -v ${target_name}/ | grep -v vendor/ | grep -v .git`

    echo_green "Format"
    gofmt -w -s ${go_files}

    echo_green "Fix"
    go tool fix ${go_files}

    echo_green "Err check"
    [ -f ${GOPATH}/bin/errcheck ] || go get -u github.com/kisielk/errcheck
    errcheck ./... | grep -v vendor

    echo_green "Lint"
    [ -f ${GOPATH}/bin/golint ] || go get -u github.com/golang/lint/golint
    for i in ${go_files}; do
        golint ${i}
    done

    echo_green "Vet"
    go tool vet ${go_files} || true

    echo_green "Misspell"
    [ -f ${GOPATH}/bin/misspell ] || go get -u github.com/client9/misspell/cmd/misspell
    misspell -source=text ${go_files}

    echo_green "Ineffassign"
    [ -f ${GOPATH}/bin/ineffassign ] || go get -u github.com/gordonklaus/ineffassign
    for i in ${go_files}; do
        ineffassign -n ${i} || true
    done

    echo_green "Gocyclo"
    [ -f ${GOPATH}/bin/gocyclo ] || go get -u github.com/fzipp/gocyclo
    gocyclo -over 15 ${go_files} || true

    echo_purple "Quality duration : $((`date +%s`-${start}))s"
}

require_clean_work_tree() {
    # Update the index
    git update-index -q --ignore-submodules --refresh
    err=0

    # Disallow unstaged changes in the working tree
    if ! git diff-files --quiet --ignore-submodules --
    then
        echo_red "cannot $1: you have unstaged changes."
        git diff-files --name-status -r --ignore-submodules -- >&2
        err=1
    fi

    # Disallow uncommitted changes in the index
    if ! git diff-index --cached --quiet HEAD --ignore-submodules --
    then
        echo_red "cannot $1: your index contains uncommitted changes."
        git diff-index --cached --name-status -r --ignore-submodules HEAD -- >&2
        err=1
    fi

    if [ ${err} = 1 ]
    then
        echo_red "Please commit or stash them."
        exit 1
    fi
}

release() {
    start=`date +%s`
    if [ "${repos%%/*}" != "github.com" ]; then
        echo "Push to '${repos%%/*}' not implemented"
        exit 1
    fi
    if [ -z "${version}" ] || [ "${version}" == "0" ]; then
        echo_red "please set version to release"
        exit 1
    fi
    if [ -z "${token}" ]; then
        echo_red "please set token to release"
        exit 1
    fi

    github_repo=${repos#*/}

    clean
    build ${osarchi}
    test
    require_clean_work_tree

    echo_green "Compress release"
    cd ${dir}/${target_name}
    for i in *-* ; do
        if [ -d "$i" ]; then
            tar czf ${i}.tar.gz ${i}
        fi
    done
    cd -

    git tag v${version} -a -m "Version $version"
    git push --tags

    sleep 5

    posturl=$(curl --data "{\"tag_name\": \"v${version}\",\"target_commitish\": \"master\",\"name\": \"v${version}\",\"body\": \"Release of version ${version}\",\"draft\": false,\"prerelease\": false}" https://api.github.com/repos/${github_repo}/releases?access_token=${access_token} | grep "\"upload_url\"" | sed -ne 's/.*\(http[^"]*\).*/\1/p')

    for i in ${dir}/${target_name}/*.tar.gz ; do
        fullpath=$(ls ${i})
        filename=${fullpath##*/}
        curl -i -X POST -H "Content-Type: application/x-gzip" --data-binary "@${fullpath}" "${posturl%\{?name,label\}}?name=${filename}&label=${filename}&access_token=${access_token}"
    done
    echo_purple Release duration : $((`date +%s`-${start}))s
}

test() {
    start=`date +%s`
    echo_green "Testing"
    godep go test -cover ${dir}

    echo_purple "Test duration : $((`date +%s`-${start}))s"
}

#########################################
#########################################

global_start=`date +%s`

read -d '' helper <<EOF || true
Usage: gomake [-v version][-t token] command...

  command...                commands to run among clean, build, quality, test, release
                            default is : 'clean build test quality'
  -v, --version=version     version of the app
  -h, --help                this helper
  -t, --token=token         token to push releases
EOF

target_name=dist
dir=$( dirname "$0" )
full_dir=$(cd "${dir}"; pwd)
app=$(basename ${full_dir})
repo=$(git config --get remote.origin.url | sed -n 's/.*@\(.*\)\.git/\1/p' | tr : /)
osarchi="$(go env GOHOSTOS)-$(go env GOHOSTARCH)"
release_osarchi="linux-amd64,darwin-amd64,windows-amd64"
version=0
access_token=

if [ -f ${dir}/gomake.cfg ]; then
 . ${dir}/gomake.cfg
fi

commands=()
while [ $# -gt 0 ]; do
    case "${1}" in
        -h|--help)
            echo "${helper}"
            exit 0
            ;;
        --version=*)
            version="${1#*=}"
            shift
            ;;
        --token=*)
            token="${1#*=}"
            shift
            ;;
        -v)
            version="${2}"
            [ $# -gt 1 ] || (echo_red "Missing argument for version"; exit 1)
            shift 2
            ;;
        -t)
            token="${2}"
            [ $# -gt 1 ] || (echo_red "Missing argument for token"; exit 1)
            shift 2
            ;;
        --)
            shift
            commands+=("${@}")
            break
            ;;
        *)
            commands+=("${1}")
            shift
            ;;
    esac
done


if [ ${#commands[@]} -eq 0 ]; then
    commands=(clean build test quality)
fi

command_count=0
for i in "${commands[@]}"; do
    case ${i} in
        test|build|release|clean|quality)
            ${i}
            ((++command_count))
        ;;
        *)
            echo_red "Unknown command '${i}'"
            echo ${helper}
            exit 1
        ;;
    esac
done

if [ ${command_count} -gt 1 ]; then
    echo_purple "Global duration : $((`date +%s`-global_start))s"
fi

exit 0
