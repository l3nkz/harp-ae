# HARP Artifact Evaluation

Within this repository you will find the scripts and necessary information
to validate the artifacts of the HARP Middleware paper.

## Preparation

In order to perform the evaluation of the HARP paper, various preparations have to be done.

### System Setup

Both systems the Odroid as well as the Raptor Lake need a special Linux kernel for the baseline measurements.
Follow the below steps to build and install these kernels. Reboot and verify with `uname -a` that the correct
kernel is running.

#### Odroid

If necessary install all packages to build a Linux kernel. This depends on your distribution.
If using Arch Linux, you can use the following commands

```
sudo pacman -Sy base-devel
```

Clone the following repository and switch to the `odroidxu3-6.6` branch:

```
git clone https://github.com/l3nkz/linux.git
cd linux
git checkout odroidxu3-6.6
```

Copy the sample config file to `.config` and build the kernel

```
cp config.odroid.sample .config
make
make dtbs
```

Last, install the kernel and the generated device tree to your boot partition and make it the
default boot option. This part depends on your distribution. For Arch Linux you can use the
following steps.

```
make tarzst-pkg
sudo pacman -U *.pkg.tar.zst
```

#### Raptor Lake

If necessary install all packages to build a Linux kernel. This depends on your distribution.
If you use Debian use the following command:

```
sudo apt-get install packaging-dev build-essential linux-source bc kmod cpio flex libncurses5-dev libelf-dev libssl-dev dwarves bison
```

Clone the following repository and switch to the `intel-itd` branch

```
git clone https://github.com/l3nkz/linux.git
cd linux
git checkout linux-itd
```

Copy the sample config file to `.config` and build the kernel

```
cp config.raptorlake.sample .config
make
```

Last, install the kernel to your boot partition and make it the default boot option.
This part depends on your distribution. For Debian you can use the following steps:

```
make bindeb-pkg
dpkg -i linux-image.*.deb
```

### Compiling HARP

Clone the repository or use the provided tar file.

`git clone https://github.com/l3nkz/harp.git` or `wget os.inf.tu-dresden.de/~tsmejkal/harp.tar.gz && tar -xaf harp.tar.gz`

Install all of HARP's dependencies. This depends on your distribution.

- cmake
- libprotobuf
- protobufc
- yamplcpp
- eigen
- libtbb

Alternatively, you could also use the nix flake shipped with the project (only x86).

Build HARP and libharp with the following commands:

```
mkdir build && cd build
cmake -DCMAKE_INSTALL_PREFIX=~/harp ..
make
make install
```

When everything compiles correctly, the library files should be located in the base directory in `lib`
and the HARP server binaries in the base directory in `bin`.

### Compiling Benchmarks

The HARP paper evaluates the resource manager with different benchmarks which have to be build and prepared separately.

#### NPB

Install the necessary dependencies for the NPB benchmark:

- gcc
- gfortran

Download the sources of the NPB benchmark suite and build it as
follows (similar to the NPB documentation):

```
wget https://www.nas.nasa.gov/assets/npb/NPB3.4.3.tar.gz
tar -xaf NPB3.4.3.tar.gz
cd NPB3.4.3/NPB3.4-OMP
cp config/make.def.sample config/make.def && cp config/suite.def.sample config/suite.def
sed -i 's/S$/C/g' # Use C here for the Raptor Lake or A for the Odroid
make suite
```

The final binaries are available in the base directory in `bin`.

#### Intel TBB

*These benchmarks are only needed to evaluate the Raptor Lake system.*

Clone the sources of Intel TBB and build the benchmarks which are used to evaluate HARP using
the following steps (similar to the Intel TBB documentation):

```
git clone https://github.com/oneapi-src/oneTBB.git
cd oneTBB/examples
for b in "graph/binpack" "parallel_for/seismic" "parallel_for_each/parallel_preorder" "parallel_reduce/pi"\
         "parallel_reduce/primes" "task_arena/fractal"; do
    (
        cd $b
        mkdir build && cd build
        cmake ..
        make
    )
done
```

#### KPN

*These benchmarks are only needed to evaluate the Odroid system.*

Download the sources for the KPN framework and the benchmarks and compile them as follows:

First the KPN framework
```
wget https://os.inf.tu-dresden.de/~tsmejkal/dpm.tar.gz && tar -xaf dpm.tar.gz
cd dpm
mkdir build && cd build
cmake -DCMAKE_PREFIX_PATH=~/harp -DCMAKE_INSTALL_PREFIX=~/harp ..
make
make install
```

Second the KPN Benchmarks
```
wget https://os.inf.tu-dresden.de/~tsmejkal/dpm-demos.tar.gz && tar -xaf dpm-demo.tar.gz
cd dpm-demo
for b in "LMS" "LMS-static-4" "Mandelbrot" "Mandelbrot-static-4"; do
    (
        cd $b
        mkdir build && cd build
        cmake -DCMAKE_PREFIX_PATH=~/harp ..
        make
    )
done
```

The benchmark binaries are then located in the corresponding subfolders.

#### Tensorflow

*These benchmarks ore only needed to evaluate the Raptor Lake system.*

The Tensorflow benchmarks are python based benchmarks. In order to not clutter your python
environment with useless packages, we recommend using a virtualenv for example using the
`virtualenv_wrapper` script.

To create and activate the virtualenv use the following commands.
```
mkvirtualenv harp
workon harp
```

Install the python harp library. They are included in the HARP directory

```
cd harp/py_client
pip install .
```

Now download the HARP-enabled TF-Lite repository and install the TF-Lite library in the same
virtualenv.

```
wget https://os.inf.tu-dresden.de/~tsmejkal/harp-tflite.tar.gz && tar -xaf harp-tflite.tar.gz
cd harp-tflite
pip install .
```

### Preparing the Measurement Environment

Before running the measurements, you first need to select the evaluation platform by copying the
sample configuration file to 'config.sh.inc'. For the Odroid platform choose the 'config.odroid.sample'
file and for the Raptor Lake platform the 'config.raptor.sample' file.

Next, copy the benchmark files in the 'bench' directory and the HARP binaries to the 'bin' directory
and the HARP libraries to the 'lib' directory. See the Readmes of the corresponding sub-directories of
this repository for more information.


### Preparing the Hardware

Before you can run the measurement script, you need to setup the environment. Run the `prepare.sh`
script from this repository as root to setup the necessary configs.

```
sudo ./prepare.sh
```

## (Optional) Build the Offline Operating Point Tables

In order to use the HARP RM with offline generated operating points these need to be generated. For 
that one has to execute all benchmarks at all possible configurations and record various hardware
properties. The following commands will generate the necessary tables. Be aware that this step takes
a significant amount of time (~1w). Alternatively one can also use the operating point tables shipped
with this repository.

```
./measure-offline.sh
```

This command will create a folder with the current date and time containing all the data from this
measurement step.

### Generate Offline Operating Point Tables from Measurements

Once the benchmarks are measured at the possible hardware configurations, the next step is to extract
the necessary information from the measurements, Pareto-optimize them and generate corresponding OP tables
from that. Use the following command:

```
./construct_optables.py -i <result_dir> -p odroid|raptor -o platforms
```

This python script requires the 'parotoset','pandas', and 'yaml' python packages. Either install them to
your system or use an appropriate python environment.

## Run the Measurement

In order run the whole measurement suite just run the following command. Be aware that this step takes
a significant amount of time (~4d).

```
./measure.sh
```

This command will create a folder with the current date and time containing all the data from the measurement.
This includes logs from the HARP RM, logs from the benchmarked binaries as well as traces from the resource 
assignments and the operating point databases. In addition to these debugging data, this folder will also have
a 'results' subfolder containing the measurement results of all the measured scenarios.

## Post Process the Data and Generate Plots

The measurements produced results for the various figures in the paper. However, the data requires some additional
post processing. First we need to collect the results from the two platforms.

```
mkdir results
scp odroid:ae/<result-dir>/*.csv results/odroid
scp raptor:ae/<result-dir>/*.csv results/raptor
```

On the Raptor Lake platform we additionally need to separate the results for the learning experiment.

```
mkdir results/learning
mv results/raptor/learning_*.csv results/learning
```

### Improvement Factor Plots

After finishing the measurement and collecting the results, run the following python script to post process the
measurement data from the two platforms and extract the improvement factors for energy consumption and makespan:

```
./postprocess.py -i results/odroid -o figures/data/odroid
./postprocess.py -i results/raptor -o figures/data/raptor
```

This script requires the 'pandas' and 'scipy' python packages. Either install them to your system or use an appropriate
python environment.

To build the figures, switch in the figures folder and run the following command:

```
cd figures
pdflatex improplots.tex
pdflatex improplots.tex
```

This should create a file 'improplots.pdf' containing the improvement plots as used in the paper.

### Learning Graphs

For the learning graphs we also need to do some post processing. Run the following python script first to collect the
necessary data from the individual measurements:

```
./postprocess-learn.py -b results/raptor -l results/learning -o figures/data/learning
```

To build the learning graphs switch in the figures folder and run the following command:

```
cd figures
Rscript learnplots.R data/learning/learn.csv data/learning/base.csv
```

This should create a file 'learnplots.pdf' containing the learning graphs as used in the paper.

### Comparing to Paper Figures

The repository also contains the raw results that we used for the paper. They are provided in 
the folder `paper_results`. Accordingly, following the same steps as described before, one 
can also generate the figures from the paper.
