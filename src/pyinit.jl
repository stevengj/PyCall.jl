# Initializing Python (surprisingly complicated; see also deps/build.jl)

#########################################################################

# global PyObject constants, initialized to NULL and then overwritten in __init__
# (eventually, the ability to define global const in __init__ may go away,
#  and in any case this is better for type inference during precompilation)
const inspect = PyNULL()
const builtin = PyNULL()
const BuiltinFunctionType = PyNULL()
const MethodType = PyNULL()
const MethodWrapperType = PyNULL()
const ufuncType = PyNULL()
const format_traceback = PyNULL()
const pyproperty = PyNULL()
const jlfun2pyfun = PyNULL()
const c_void_p_Type = PyNULL()

# other global constants initialized at runtime are defined via Ref
# or are simply left as non-const values
const pynothing = Ref{PyPtr}(0)
const pyxrange = Ref{PyPtr}(0)

#########################################################################
# initialize jlWrapType for pytype.jl

#########################################################################
# Virtual environment support

venv_python(::Nothing) = pyprogramname

function venv_python(venv::AbstractString, suffix::AbstractString = "")
    # `suffix` is used to insert version number (e.g., "3.7") in tests
    # (see ../test/test_venv.jl)
    if Sys.iswindows()
        return joinpath(venv, "Scripts", "python$suffix.exe")
    else
        return joinpath(venv, "bin", "python$suffix")
    end
    # "Scripts" is used only in Windows and "bin" elsewhere:
    # https://github.com/python/cpython/blob/3.7/Lib/venv/__init__.py#L116
end

"""
    python_cmd(args::Cmd = ``; venv, python) :: Cmd

Create an appropriate `Cmd` for running Python program with command
line arguments `args`.

# Keyword Arguments
- `venv::String`: The path of a virtualenv to be used instead of the
  default environment with which PyCall isconfigured.
- `python::String`: The path to the Python executable.  `venv` is ignored
  when this argument is specified.
"""
function python_cmd(args::Cmd = ``;
                    venv::Union{Nothing, AbstractString} = nothing,
                    python::AbstractString = venv_python(venv))
    return pythonenv(`$python $args`)
end

function find_libpython(python::AbstractString)
    script = joinpath(@__DIR__, "..", "deps", "find_libpython.py")
    cmd = python_cmd(`$script`; python = python)
    try
        return read(cmd, String)
    catch
        return nothing
    end
end

#########################################################################

const _finalized = Ref(false)
# This flag is set via `Py_AtExit` to avoid calling `pydecref_` after
# Python is finalized.

function _set_finalized()
    # This function MUST NOT invoke any Python APIs.
    # https://docs.python.org/3/c-api/sys.html#c.Py_AtExit
    _finalized[] = true
    return nothing
end

function Py_Finalize()
    pygui_stop_all()
    ccall(@pysym(:Py_Finalize), Cvoid, ())
end

function __init__()
    # Clear out global states.  This is required only for PyCall
    # AOT-compiled into system image.
    _finalized[] = false
    empty!(_namespaces)
    empty!(eventloops)
    global npy_initialized = false
    empty!(npy_api)
    empty!(pycall_gc)
    empty!(pyexc)
    empty!(pytype_queries)
    # empty!(permanent_strings)

    # sanity check: in Pkg for Julia 0.7+, the location of Conda can change
    # if e.g. you checkout Conda master, and we'll need to re-build PyCall
    # for something like pyimport_conda to continue working.
    if conda && dirname(python) != abspath(Conda.PYTHONDIR)
        error("Using Conda.jl python, but location of $python seems to have moved to $(Conda.PYTHONDIR).  Re-run Pkg.build(\"PyCall\") and restart Julia.")
    end

    # issue #189
    libpy_handle = libpython === nothing ? C_NULL :
        Libdl.dlopen(libpython, Libdl.RTLD_LAZY|Libdl.RTLD_DEEPBIND|Libdl.RTLD_GLOBAL)

    already_inited = 0 != ccall((@pysym :Py_IsInitialized), Cint, ())

    if !already_inited
        pyhome = PYTHONHOME

        if isfile(get(ENV, "PYCALL_JL_RUNTIME_PYTHON", ""))
            _current_python[] = ENV["PYCALL_JL_RUNTIME_PYTHON"]

            # Check libpython compatibility.
            venv_libpython = find_libpython(current_python())
            if venv_libpython === nothing
                error("""
                `libpython` for $(current_python()) cannot be found.
                PyCall.jl cannot initialize Python safely.
                """)
            elseif venv_libpython != libpython
                error("""
                Incompatible `libpython` detected.
                `libpython` for $(current_python()) is:
                    $venv_libpython
                `libpython` for $pyprogramname is:
                    $libpython
                PyCall.jl only supports loading Python environment using
                the same `libpython`.
                """)
            end

            if haskey(ENV, "PYCALL_JL_RUNTIME_PYTHONHOME")
                pyhome = ENV["PYCALL_JL_RUNTIME_PYTHONHOME"]
            else
                pyhome = pythonhome_of(current_python())
            end
        elseif conda && Sys.iswindows()
            # some Python modules on Windows need the PATH to include
            # Anaconda's Library\bin directory in order to find their DLL files
            ENV["PATH"] = Conda.bin_dir(Conda.ROOTENV) * ";" * get(ENV, "PATH", "")
        end

        Py_SetPythonHome(libpy_handle, pyversion, pyhome)
        Py_SetProgramName(libpy_handle, pyversion, current_python())
        ccall((@pysym :Py_InitializeEx), Cvoid, (Cint,), 0)
    end

    # Will get reinitialized properly on first use
    Sys.iswindows() && (PyActCtx[] = C_NULL)

    # Make sure python wasn't upgraded underneath us
    new_pyversion = vparse(split(unsafe_string(ccall(@pysym(:Py_GetVersion),
                               Ptr{UInt8}, ())))[1])

    if new_pyversion.major != pyversion.major
        error("PyCall precompiled with Python $pyversion, but now using Python $new_pyversion; ",
              "you need to relaunch Julia and re-run Pkg.build(\"PyCall\")")
    end

    copy!(inspect, pyimport("inspect"))
    copy!(builtin, pyimport(pyversion.major < 3 ? "__builtin__" : "builtins"))
    copy!(pyproperty, pybuiltin(:property))

    capi_init()
    pyexc_initialize() # mappings from Julia Exception types to Python exceptions

    # cache Python None -- PyPtr, not PyObject, to prevent it from
    # being finalized prematurely on exit
    pynothing[] = @pyglobalobj(:_Py_NoneStruct)

    # xrange type (or range in Python 3)
    pyxrange[] = @pyglobalobj(:PyRange_Type)

    # ctypes.c_void_p for Ptr types
    copy!(c_void_p_Type, pyimport("ctypes")."c_void_p")

    # traceback.format_tb function, for show(PyError)
    copy!(format_traceback, pyimport("traceback")."format_tb")

    init_datetime()
    pyjlwrap_init()

    # jlwrap is a class, and when assigning it to an object
    #    obj[:foo] = some_julia_function
    # it won't behave like a regular Python method because it's not a Python
    # function (in particular, `self` won't be passed to it). The solution is:
    #    obj[:foo] = jlfun2pyfun(some_julia_function)
    # This is a bit of a kludge, obviously.
    copy!(jlfun2pyfun,
          pyeval_("""lambda f: lambda *args, **kwargs: f(*args, **kwargs)"""))

    if !already_inited
        # some modules (e.g. IPython) expect sys.argv to be set
        ref0 = Ref{UInt32}(0)
        GC.@preserve ref0 ccall(@pysym(:PySys_SetArgvEx), Cvoid,
                                        (Cint, Ref{Ptr{Cvoid}}, Cint),
                                        1, pointer_from_objref(ref0), 0)

        # Some Python code checks sys.ps1 to see if it is running
        # interactively, and refuses to be interactive otherwise.
        # (e.g. Matplotlib: see PyPlot#79)
        if isinteractive()
            let sys = pyimport("sys")
                if !hasproperty(sys, "ps1")
                    sys."ps1" = ">>> "
                end
            end
        end
    end

    # Configure finalization steps.
    #
    # * In julia/PyCall, `julia` needs to call `Py_Finalize` to
    #   finalize Python runtime to invoke Python functions registered
    #   in Python's exit hook.  This is done by Julia's `atexit` exit
    #   hook.
    #
    # * In PyJulia, `python` needs to call `jl_atexit_hook` in its
    #   exit hook instead.
    #
    # In both cases, it is important to not invoke GC of the finalized
    # runtime.  This is ensured by:
    @pycheckz ccall((@pysym :Py_AtExit), Cint, (Ptr{Cvoid},),
                    @cfunction(_set_finalized, Cvoid, ()))
    if !already_inited
        # Once `_set_finalized` is successfully registered to
        # `Py_AtExit`, it is safe to call `Py_Finalize` during
        # finalization of this Julia process.
        atexit(Py_Finalize)
    end
end
