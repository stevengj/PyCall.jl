# Finding python. This is slightly complicated in order to support using PyCall
# from libjulia. We check if python symbols are present in the current process
# and if so do not use the deps.jl file, getting everything we need from the
# current process instead.

proc_handle = unsafe_load(cglobal(:jl_exe_handle, Ptr{Cvoid}))

struct Dl_info
    dli_fname::Ptr{UInt8}
    dli_fbase::Ptr{Cvoid}
    dli_sname::Ptr{UInt8}
    dli_saddr::Ptr{Cvoid}
end
EnumProcessModules(hProcess, lphModule, cb, lpcbNeeded) =
    ccall(:K32EnumProcessModules, stdcall, Bool,
        (Ptr{Cvoid}, Ptr{Ptr{Cvoid}}, UInt32, Ptr{UInt32}),
        hProcess, lphModule, cb, lpcbNeeded)

symbols_present = false
@static if Sys.iswindows()
    lpcbneeded = Ref{UInt32}()
    proc_handle = ccall(:GetCurrentProcess, stdcall, Ptr{Cvoid}, ())
    handles = Vector{Ptr{Cvoid}}(undef, 20)
    if EnumProcessModules(proc_handle, handles, sizeof(handles), lpcbneeded) == 0
        resize!(handles, div(lpcbneeded[],sizeof(Ptr{Cvoid})))
        EnumProcessModules(proc_handle, handles, sizeof(handles), lpcbneeded)
    end
    # Try to find python if it's in the current process
    for handle in handles
        sym = ccall(:GetProcAddress, stdcall, Ptr{Cvoid},
            (Ptr{Cvoid}, Ptr{UInt8}), handle, "Py_GetVersion")
        sym != C_NULL || continue
        global symbols_present = true
        global libpy_handle = handle
        break
    end
else
    global symbols_present = hassym(proc_handle, :Py_GetVersion)
end

if PyPreferences.inprocess
    @assert symbols_present # TODO: better error
end

if !symbols_present
    PyPreferences.assert_configured()
    using PyPreferences: PYTHONHOME, conda, libpython, pyprogramname, python, pyversion_build
    # Only to be used at top-level - pointer will be invalid after reload
    libpy_handle = try
        Libdl.dlopen(libpython, Libdl.RTLD_LAZY|Libdl.RTLD_DEEPBIND|Libdl.RTLD_GLOBAL)
    catch err
        if err isa ErrorException
            error(err.msg, "\n", PyPreferences.instruction_message())
        else
            rethrow(err)
        end
    end
    # need SetPythonHome to avoid warning, #299
    Py_SetPythonHome(libpy_handle, pyversion_build, PYTHONHOME)
else
    @static if Sys.iswindows()
        pathbuf = Vector{UInt16}(undef, 1024)
        ret = ccall(:GetModuleFileNameW, stdcall, UInt32,
            (Ptr{Cvoid}, Ptr{UInt16}, UInt32),
            libpy_handle, pathbuf, length(pathbuf))
        @assert ret != 0
        pathlen = something(findfirst(iszero, pathbuf)) - 1
        libname = String(Base.transcode(UInt8, pathbuf[1:pathlen]))
        if (Libdl.dlopen_e(libname) != C_NULL)
            const libpython = libname
        else
            const libpython = nothing
        end
    else
        libpy_handle = proc_handle
        # Now determine the name of the python library that these symbols are from
        some_address_in_libpython = Libdl.dlsym(libpy_handle, :Py_GetVersion)
        some_address_in_main_exe = Libdl.dlsym(proc_handle, Sys.isapple() ? :_mh_execute_header : :main)
        dlinfo1 = Ref{Dl_info}()
        dlinfo2 = Ref{Dl_info}()
        ccall(:dladdr, Cint, (Ptr{Cvoid}, Ptr{Dl_info}), some_address_in_libpython,
            dlinfo1)
        ccall(:dladdr, Cint, (Ptr{Cvoid}, Ptr{Dl_info}), some_address_in_main_exe,
            dlinfo2)
        if dlinfo1[].dli_fbase == dlinfo2[].dli_fbase
            const libpython = nothing
        else
            const libpython = unsafe_string(dlinfo1[].dli_fname)
        end
    end
    # If we're not in charge, assume the user is installing necessary python
    # libraries rather than messing with their configuration
    const conda = false
    # Top-level code (`_current_python`) needs `pyprogramname`.  We
    # don't need its value but we need to assign something to it:
    const pyprogramname = ""
end

const pyversion = vparse(split(Py_GetVersion(libpy_handle))[1])

# PyUnicode_* may actually be a #define for another symbol, so
# we cache the correct dlsym
const PyUnicode_AsUTF8String =
    findsym(libpy_handle, :PyUnicode_AsUTF8String, :PyUnicodeUCS4_AsUTF8String, :PyUnicodeUCS2_AsUTF8String)
const PyUnicode_DecodeUTF8 =
    findsym(libpy_handle, :PyUnicode_DecodeUTF8, :PyUnicodeUCS4_DecodeUTF8, :PyUnicodeUCS2_DecodeUTF8)

# Python 2/3 compatibility: cache symbols for renamed functions
if hassym(libpy_handle, :PyString_FromStringAndSize)
    const PyString_FromStringAndSize = :PyString_FromStringAndSize
    const PyString_AsStringAndSize = :PyString_AsStringAndSize
    const PyString_Size = :PyString_Size
    const PyString_Type = :PyString_Type
else
    const PyString_FromStringAndSize = :PyBytes_FromStringAndSize
    const PyString_AsStringAndSize = :PyBytes_AsStringAndSize
    const PyString_Size = :PyBytes_Size
    const PyString_Type = :PyBytes_Type
end

# hashes changed from long to intptr_t in Python 3.2
const Py_hash_t = pyversion < v"3.2" ? Clong : Int

# whether to use unicode for strings by default, ala Python 3
const pyunicode_literals = pyversion >= v"3.0"

if libpython == nothing
    macro pysym(func)
        esc(func)
    end
    macro pyglobal(name)
        :(cglobal($(esc(name))))
    end
    macro pyglobalobj(name)
        :(cglobal($(esc(name)), PyObject_struct))
    end
    macro pyglobalobjptr(name)
        :(unsafe_load(cglobal($(esc(name)), Ptr{PyObject_struct})))
    end
else
    macro pysym(func)
        :(($(esc(func)), libpython))
    end
    macro pyglobal(name)
        :(cglobal(($(esc(name)), libpython)))
    end
    macro pyglobalobj(name)
        :(cglobal(($(esc(name)), libpython), PyObject_struct))
    end
    macro pyglobalobjptr(name)
        :(unsafe_load(cglobal(($(esc(name)), libpython), Ptr{PyObject_struct})))
    end
end
