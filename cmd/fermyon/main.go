package main

import (
	"bytes"
	_ "embed"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	"github.com/lima-vm/lima/pkg/store/dirnames"
	"github.com/sirupsen/logrus"
	"github.com/spf13/cobra"
)

const (
	DefaultInstanceName = "spin"
)

//go:embed templates/spin.yaml
var spinTemplate []byte

func main() {

	if err := newApp().Execute(); err != nil {
		handleExitCoder(err)
		logrus.Fatal(err)
	}
}

func newApp() *cobra.Command {
	// if exe, err := os.Executable(); err == nil {
	// 	// binDir := filepath.Dir(exe)
	// 	// prefixDir := filepath.Dir(binDir)
	// }
	//limactl_command, err = findLimactl()

	var rootCmd = &cobra.Command{
		Use:     "fermyon",
		Short:   "Fermyon local dev installer",
		Version: "0.0.1",
		Example: fmt.Sprintf(`  Start the default instance:
  $ fermyon up

  Export environment:
  $ fermyon environment

  List Fermyon service status:
  $ fermyon status

  Stop the default instance:
  $ fermyon down
`),
		SilenceUsage:  true,
		SilenceErrors: true,
	}
	rootCmd.PersistentFlags().Bool("debug", false, "debug mode")
	rootCmd.PersistentPreRunE = func(cmd *cobra.Command, args []string) error {
		debug, _ := cmd.Flags().GetBool("debug")
		if debug {
			logrus.SetLevel(logrus.DebugLevel)
		}
		if os.Geteuid() == 0 {
			return errors.New("must not run as the root")
		}
		// Make sure either $HOME or $LIMA_HOME is defined, so we don't need
		// to check for errors later
		if _, err := dirnames.LimaDir(); err != nil {
			return err
		}
		return nil
	}
	rootCmd.AddCommand(
		newUpCommand(),
		newDownCommand(),
		newEnvironmentCommand(),
		newStatusCommand(),
	)
	return rootCmd
}

type ExitCoder interface {
	error
	ExitCode() int
}

func handleExitCoder(err error) {
	if err == nil {
		return
	}

	if exitErr, ok := err.(ExitCoder); ok {
		os.Exit(exitErr.ExitCode())
		return
	}
}

func newUpCommand() *cobra.Command {
	var upCommand = &cobra.Command{
		Use: "up",
		Example: `
$ fermyon up
`,
		Short: "Start an instance of Fermyon",
		Args:  cobra.MaximumNArgs(1),
		RunE:  upAction,
	}
	return upCommand
}

func newDownCommand() *cobra.Command {
	var downCommand = &cobra.Command{
		Use: "down",
		Example: `
$ fermyon down
`,
		Short: "Stop an instance of Fermyon",
		Args:  cobra.MaximumNArgs(1),
		RunE:  downAction,
	}
	return downCommand
}

func newEnvironmentCommand() *cobra.Command {
	var environmentCommand = &cobra.Command{
		Use: "environment",
		Example: `
$ fermyon environment
`,
		Short: "Get environment variables to help with local dev for Spin",
		Args:  cobra.MaximumNArgs(1),
		RunE:  environmentAction,
	}
	return environmentCommand
}

func newStatusCommand() *cobra.Command {
	var statusCommand = &cobra.Command{
		Use: "status",
		Example: `
$ fermyon status
`,
		Short: "Validate the Fermyon service status",
		Args:  cobra.MaximumNArgs(1),
		RunE:  statusAction,
	}
	return statusCommand
}

func upAction(cmd *cobra.Command, args []string) error {
	var limaDir, _ = dirnames.LimaDir()
	var directory = filepath.Join(limaDir, "spin")
	os.MkdirAll(directory, 0744)
	var file = filepath.Join(directory, "lima.yaml")
	os.WriteFile(file, spinTemplate, 0644)
	upArgs := [4]string{"limactl", "start", "--name", "spin"}
	return shellOut(cmd, upArgs[:])

}

func downAction(cmd *cobra.Command, args []string) error {
	downArgs := [3]string{"limactl", "stop", "spin"}
	return shellOut(cmd, downArgs[:])
}

func environmentAction(cmd *cobra.Command, args []string) error {
	exportVars := `
Adding these variables to your shell environment will enable the spin CLI to target your local development VM.

export HIPPO_URL=http://hippo.local.fermyon.link/
export BINDLE_URL=http://bindle.local.fermyon.link/v1
`
	cmd.OutOrStdout().Write([]byte(exportVars))
	return nil
}

func statusAction(cmd *cobra.Command, args []string) error {
	cmd.OutOrStdout().Write([]byte("Lima VM List:\n"))
	limaStatusArgs := [2]string{"limactl", "list"}
	if err := shellOut(cmd, limaStatusArgs[:]); err != nil {
		return err
	}
	cmd.OutOrStdout().Write([]byte("\nConsul Member Status:\n"))
	consulStatusArgs := [6]string{"limactl", "shell", "spin", "consul", "members", "status"}
	if err := shellOut(cmd, consulStatusArgs[:]); err != nil {
		return err
	}
	cmd.OutOrStdout().Write([]byte("\nNomad Job Status:\n"))
	nomadStatusArgs := [5]string{"limactl", "shell", "spin", "nomad", "status"}
	if err := shellOut(cmd, nomadStatusArgs[:]); err != nil {
		return err
	}
	cmd.OutOrStdout().Write([]byte("\nHippo Health Endpoint:\n"))
	hippoHealthCheckArgs := []string{"curl", "http://hippo.local.fermyon.link/healthz"}
	if err := shellOut(cmd, hippoHealthCheckArgs[:]); err != nil {
		return err
	}
	return nil
}

func shellOut(cmd *cobra.Command, args []string) error {
	limaCmd := exec.Command(args[0], args[1:]...)

	var output bytes.Buffer
	limaCmd.Stdout = &output

	var stderr bytes.Buffer
	limaCmd.Stderr = &stderr

	err := limaCmd.Run()

	cmd.OutOrStdout().Write(output.Bytes())
	cmd.ErrOrStderr().Write(stderr.Bytes())

	if err != nil {
		return err
	}
	return nil
}
