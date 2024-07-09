# Goa - *goal, but reached a little bit sooner*

Goa is a command-line-based workflow tool for the development of applications
for the [Genode OS Framework](https://genode.org). It streamlines the work of
cross-developing Genode application software using a GNU/Linux-based host
system for development, in particular:

* Importing 3rd-party source code

* Building software using commodity build systems such as CMake

* Test-running software on the host system

* Crafting runtime configurations for deployment

* Packaging and publishing the software for the integration into Genode
  systems like [Sculpt OS](https://genode.org/download/sculpt)

Goa is solely geared towards application software. It does ***not*** address the
following topics:

* Integration of complete Genode systems

* Test automation

* Continuous testing and integration (CI)

Those topics are covered by the tools that come with the Genode project and
are described in Chapter 5 of the 
[Genode Foundations book](https://genode.org/documentation/genode-foundations/23.05/development/index.html)


# Installation

### Install the latest Genode tool chain on a GNU/Linux OS on a 64-bit x86 PC.
  It is recommended to use the latest long-term support (LTS) version of
  Ubuntu. Make sure that your installation satisfies the following
  requirements.

  * `libSDL-dev` needed to run system scenarios directly on your host OS,
  * `tclsh` and `expect` needed by the tools,
  * `xmllint` for validating configurations,

### Clone the Goa repository:

```sh
$ git clone https://github.com/genodelabs/goa.git
```

  The following steps refer to the directory of the clone as `<goa-dir>`.

### Enable your shell to locate the 'goa' tool by either

  * Creating a symbolic link in one of your shell's binary-search
    locations (e.g., if you use a `bin/` directory in your home directory,
    issue `ln -s <goa-dir>/bin/goa ~/bin/`), or alternatively

  * Add `<goa-dir>/bin/>` to your `PATH` environment variable, e.g.,
    (replace `<goa-dir>` with the absolute path of your clone):

```sh
$ export PATH=$PATH:<goa-dir>/bin
```

### Optionally, enable bash completion by adding the following line to your
  `~/.bashrc` file:

```sh
$ source <goa-dir>/share/bash-completion/goa
```

## Usage

Once installed, obtain further information about the use of Goa via the command:

```sh
$ goa help
```

# Step-by-step tutorials

The following article series gets you started with using Goa.

[Streamlining the development of Genode applications](https://genodians.org/nfeske/2019-11-25-goa)

[Sticking together a little Unix (part 1)](https://genodians.org/nfeske/2019-12-13-goa-unix-bash)

[Sticking together a little Unix (part 2)](https://genodians.org/nfeske/2019-12-19-goa-unix-terminal)

[Sticking together a little Unix (part 3)](https://genodians.org/nfeske/2019-12-22-goa-unix-pipes)

[Publishing packages](https://genodians.org/nfeske/2020-01-16-goa-publish)
