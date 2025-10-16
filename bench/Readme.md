# HARP Artifact Evaluation - Benchmark Folder

This folder should contain the benchmark binaries. Build the benchmarks according to the
main Readme file and copy the resulting binaries to this directory. Read carefully the
following instructions as well to make sure that the benchmarks are executed as expected,
because some of them require additional command line arguments or other configuration.

## NPB Benchmarks

Copy the binaries and rename them to remove the '.x' suffix.

```
for b in bt cg ep ft is lu mg sp ua; do
    # Raptor Lake uses class C
    if [ -e "${b}.C.x" ]; then
        mv "${b}.C.x" "${b}"
    fi

    # Odroid uses class A
    if [ -e "${b}.A.x" ]; then
        mv "${b}.A.x" "${b}"
    fi
done
```

## Intel TBB Benchmarks (only Raptor Lake)

These benchmarks require additional command line arguments. After copying the binaries
to this directory from the Intel TBB source dir, also copy the '\*.args' files from the
'raptor.support' folder.

## Tensorflow (only Raptor Lake)

These benchmarks are slightly special as they are binaries with built-in HARP support.
After setting them up, you don't need to copy them to this directory instead copy the
'alexnet' and 'vgg' scripts from the 'raptor.support' folder to this directory.

## KPN Benchmarks (only Odroid)

Similar to the Tensorflow benchmarks, the KPN benchmarks also have built-in HARP support.
Hence they also need some additional care when being started. For that, build the benchmarks
as described in the main Readme file and copy them to this directory. Rename them so that
the have an '.x' suffix:

```
for b in lms lms-static mandelbrot mandelbrot-static; do
    mv "$b" "$b.x"
done
```

Afterwards, copy the starter scripts from the 'odroid.support' folder to this directory.
