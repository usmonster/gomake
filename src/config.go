package main

type Config struct {
	targetDirectory string
}

func newConfig() *Config {
	return &Config{
		targetDirectory: "/dist",
	}
}