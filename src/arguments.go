package main

import (
	"github.com/blablacar/dgr/bin-dgr/common"
	"github.com/n0rad/go-erlog/data"
	"github.com/n0rad/go-erlog/errs"
	"github.com/n0rad/go-erlog/logs"
	"github.com/spf13/cobra"
	"io/ioutil"
	"os"
	"strings"
)

var workPath string

//var all = &cobra.Command{
//	Use:   "clean",
//	Short: "clean build",
//	Long:  `clean build, including rootfs`,
//	Run: func(cmd *cobra.Command, args []string) {
//		newProject(workPath).clean()
//	},
//}
//
//var cleanCmd = &cobra.Command{
//	Use:   "clean",
//	Short: "clean build",
//	Long:  `clean build, including rootfs`,
//	Run: func(cmd *cobra.Command, args []string) {
//		newProject(workPath).clean()
//	},
//}

func prepareArgParser() (*cobra.Command, error) {
	var err error
	var version bool
	var logLevel string
	var __ string

	var rootCmd = &cobra.Command{
		Use: "gomake",
		Run: func(cmd *cobra.Command, args []string) {
			cmd.Help()
			os.Exit(1)
		},
		PersistentPreRun: func(cmd *cobra.Command, args []string) {
			if version {
				displayVersionAndExit()
			}

		},
	}

	rootCmd.PersistentFlags().StringVarP(&__, "log-level", "L", "info", "Set log level")
	logLevel, err = discoverStringArgument("L", "log-level", "info")
	if err != nil {
		return nil, err
	}

	level, err := logs.ParseLevel(logLevel)
	if err != nil {
		return nil, errs.WithEF(err, data.WithField("input", logLevel), "Cannot set log level")
	}
	logs.SetLevel(level)

	rootCmd.PersistentFlags().StringVarP(&__, "work-path", "W", ".", "Set the work path")
	workPath, err = discoverStringArgument("W", "work-path", ".")
	if err != nil {
		return nil, err
	}

	rootCmd.PersistentFlags().BoolVarP(&version, "version", "V", false, "Display dgr version")

	if files, err := ioutil.ReadDir(workPath + "/scripts"); err == nil {
		logs.WithField("path", workPath+"/scripts").Debug("Found scripts directory")
		for _, file := range files {
			if !file.IsDir() && strings.HasPrefix(file.Name(), "command-") {
				scriptFullPath := workPath + "/scripts/" + file.Name()
				files2 := strings.Split(file.Name()[len("command-"):], ".")
				cmd := &cobra.Command{
					Use:   files2[0],
					Short: "Run command from " + scriptFullPath,
					Run: func(cmd *cobra.Command, args []string) {
						common.ExecCmd(scriptFullPath, args...)
					},
				}
				rootCmd.AddCommand(cmd)
			}
		}
	}

	//rootCmd.AddCommand(cleanCmd)
	return rootCmd, nil
}

func discoverStringArgument(shortName string, longName string, defaultValue string) (string, error) {
	workPathArgument := "--" + longName
	workPathArgumentAttached := workPathArgument + "="
	shortNameArgument := "-" + shortName
	for i := 1; i < len(os.Args); i++ {
		if os.Args[i] == "--" {
			return defaultValue, nil
		} else if os.Args[i] == shortNameArgument || os.Args[i] == workPathArgument {
			if len(os.Args) <= i+1 {
				return defaultValue, errs.With("Missing --" + longName + " (-" + shortName + ") value")
			}
			return os.Args[i+1], nil
		} else if strings.HasPrefix(os.Args[i], workPathArgumentAttached) {
			return os.Args[i][len(workPathArgumentAttached):], nil
		}
	}
	return defaultValue, nil
}