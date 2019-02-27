FC=gfortran

EXECUTABLE=
MAIN_SOURCE=
LIBRARIES_TO_LINK=
OPT=fast
PARALLEL=omp
SOURCES=omp_fort.f90
OBJECTS=omp_fort.so
MODULES=omp_fort
COMMS_FLAGS=
F2PY_FLAGS=
DEBUG=
PROFILE=
FFLAGS=

ifeq ($(DEBUG),true)
FFLAGS+= -Ddebug -Wall -fcheck=all -g
OPT=0
endif

ifeq ($(OPT), fast)
FFLAGS+= -O3 -funroll-loops
endif

ifeq ($(PARALLEL), serial)

else ifeq ($(PARALLEL), mpi)
FFLAGS += -DMPI
else ifeq ($(PARALLEL), omp)
COMMS_FLAGS+= -fopenmp
F2PY_FLAGS+= -lgomp
else ifeq ($(PARALLEL), ompmpi)
FFLAGS += -DMPI
FFLAGS+= -fopenmp
else
$(error Unrecognised parallel option:  $(PARALLEL))
exit 1
endif

ifeq ($(PROFILE),true)
FFLAGS+= -pg
endif

.PHONY: clean remake all

all: $(OBJECTS)

remake: clean all

clean:
	rm -rf $(OBJECTS) $(MODULES) $(EXECUTABLE)

%.so: %.f90
	f2py -m $* --f90flags='$(COMMS_FLAGS) $(FFLAGS)' $(F2PY_FLAGS) -c $< 
