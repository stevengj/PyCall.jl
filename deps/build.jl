# In this file, we figure out how to link to Python (surprisingly complicated)
# and generate a deps/deps.jl file with the libpython name and other information
# needed for static compilation of PyCall.

# As a result, if you switch to a different version or path of Python, you
# will probably need to re-run Pkg.build("PyCall").

using VersionParsing
import Conda, Libdl

struct UseCondaPython <: Exception end

include("buildutils.jl")
include("depsutils.jl")

#########################################################################

# we write configuration files only if they change, both
# to prevent unnecessary recompilation and to minimize
# problems in the unlikely event of read-only directories.
function writeifchanged(filename, str)
    if !isfile(filename) || read(filename, String) != str
        @info string(abspath(filename), " has been updated")
        write(filename, str)
    else
        @info string(abspath(filename), " has not changed")
    end
end

# return the first arg that exists in the PATH
function whichfirst(args...)
    for x in args
        if Sys.which(x) !== nothing
            return x
        end
    end
    return ""
end

const prefsfile = joinpath(first(DEPOT_PATH), "prefs", "PyCall")
mkpath(dirname(prefsfile))

try # make sure deps.jl file is removed on error
    python = try
        let py = get(ENV, "PYTHON", isfile(prefsfile) ? readchomp(prefsfile) :
                     (Sys.isunix() && !Sys.isapple()) ?
                     whichfirst("python3", "python") : "Conda"),
            vers = isempty(py) || py == "Conda" ? v"0.0" : vparse(pyconfigvar(py,"VERSION","0.0"))
            if vers < v"2.7"
                if isempty(py) || py == "Conda"
                    throw(UseCondaPython())
                else
                    error("Python version $vers < 2.7 is not supported")
                end
            end

            # check word size of Python via sys.maxsize, since a common error
            # on Windows is to link a 64-bit Julia to a 32-bit Python.
            pywordsize = parse(UInt64, pysys(py, "maxsize")) > (UInt64(1)<<32) ? 64 : 32
            if pywordsize != Sys.WORD_SIZE
                error("$py is $(pywordsize)-bit, but Julia is $(Sys.WORD_SIZE)-bit")
            end

            py
        end
    catch e1
        if isa(e1, UseCondaPython)
            @info string("Using the Python distribution in the Conda package by default.\n",
                 "To use a different Python version, set ENV[\"PYTHON\"]=\"pythoncommand\" and re-run Pkg.build(\"PyCall\").")
        else
            @info string( "No system-wide Python was found; got the following error:\n",
                  "$e1\nusing the Python distribution in the Conda package")
        end
        abspath(Conda.PYTHONDIR, "python" * (Sys.iswindows() ? ".exe" : ""))
    end

    use_conda = dirname(python) == abspath(Conda.PYTHONDIR)
    if use_conda
        Conda.add("numpy")
    end

    (libpython, libpy_name) = find_libpython(python)
    programname = pysys(python, "executable")

    # Get PYTHONHOME, either from the environment or from Python
    # itself (if it is not in the environment or if we are using Conda)
    PYTHONHOME = if !haskey(ENV, "PYTHONHOME") || use_conda
        pythonhome_of(python)
    else
        ENV["PYTHONHOME"]
    end

    # cache the Python version as a Julia VersionNumber
    pyversion = vparse(pyvar(python, "platform", "python_version()"))

    @info "PyCall is using $python (Python $pyversion) at $programname, libpython = $libpy_name"

    if pyversion < v"2.7"
        error("Python 2.7 or later is required for PyCall")
    end

    writeifchanged("deps.jl", """
    const python = "$(escape_string(python))"
    const libpython = "$(escape_string(libpy_name))"
    const pyprogramname = "$(escape_string(programname))"
    const pyversion_build = $(repr(pyversion))
    const PYTHONHOME = "$(escape_string(PYTHONHOME))"

    "True if we are using the Python distribution in the Conda package."
    const conda = $use_conda
    """)

    # Make subsequent builds (e.g. Pkg.update) use the same Python by default:
    writeifchanged(prefsfile, use_conda ? "Conda" : isfile(programname) ? programname : python)

    #########################################################################

catch

    # remove deps.jl (if it exists) on an error, so that PyCall will
    # not load until it is properly configured.
    isfile("deps.jl") && rm("deps.jl")
    rethrow()

end
