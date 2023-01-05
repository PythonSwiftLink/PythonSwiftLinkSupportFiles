//
//  AppDelegate.swift
//  Kivy-iOS
//
//  Created by MusicMaker on 22/09/2022.
//

import UIKit

fileprivate
func putenv(_ s: String) {
    let _count = s.utf8.count + 1
    let result = UnsafeMutablePointer<Int8>.allocate(capacity: _count)
    s.withCString { (baseAddress) in
        result.initialize(from: baseAddress, count: _count)
    }
    
    putenv(result)
}


fileprivate func export_orientation() {
    let info = Bundle.main.infoDictionary
    let orientations = info?["UISupportedInterfaceOrientations"] as? [AnyHashable]
    var result = "KIVY_ORIENTATION="
    for i in 0..<(orientations?.count ?? 0) {
        var item = orientations?[i] as? String
        item = (item as NSString?)?.substring(from: 22)
        if i > 0 {
            result = result + " "
        }
        result = result + (item ?? "")
    }
    
    putenv(result)
    print("Available orientation: \(result)")
}


//fileprivate func makeCString(from str: String) -> UnsafeMutablePointer<Int8> {
//    let count = str.utf8.count + 1
//    let result = UnsafeMutablePointer<Int8>.allocate(capacity: count)
//    str.withCString { (baseAddress) in
//        // func initialize(from: UnsafePointer<Pointee>, count: Int)
//        result.initialize(from: baseAddress, count: count)
//    }
//    return result
//}

//fileprivate func makeCString(from str: String) -> UnsafePointer<Int8> {
//    let count = str.utf8.count + 1
//    let result = UnsafeMutablePointer<Int8>.allocate(capacity: count)
//    str.withCString { (baseAddress) in
//        // func initialize(from: UnsafePointer<Pointee>, count: Int)
//        result.initialize(from: baseAddress, count: count)
//    }
//    return .init(result)
//}

@_cdecl("SDL_main")
func main(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32 {
    
    var ret: Int32 = 0
    
    chdir("YourApp")
    //let _ = PythonMain.shared
    putenv("PYTHONOPTIMIZE=2")
    putenv("PYTHONDONTWRITEBYTECODE=1")
    putenv("PYTHONNOUSERSITE=1")
    putenv("PYTHONPATH=.")
    putenv("PYTHONUNBUFFERED=1")
    putenv("LC_CTYPE=UTF-8")
    // putenv("PYTHONVERBOSE=1")
    // putenv("PYOBJUS_DEBUG=1")

    // Kivy environment to prefer some implementation on iOS platform
    putenv("KIVY_BUILD=ios")
    putenv("KIVY_WINDOW=sdl2")
    putenv("KIVY_IMAGE=imageio,tex,gif,sdl2")
    putenv("KIVY_AUDIO=sdl2")
    putenv("KIVY_GL_BACKEND=sdl2")

    // IOS_IS_WINDOWED=True disables fullscreen and then statusbar is shown
    putenv("IOS_IS_WINDOWED=False")

    #if DEBUG
    putenv("KIVY_NO_CONSOLELOG=1")
    #endif
    
    export_orientation()
    
    let resourcePath = Bundle.main.resourcePath!
    let python_home = "PYTHONHOME=\(resourcePath)"
    putenv(python_home)
    let python_path = "PYTHONPATH=\(resourcePath):\(resourcePath)/lib/python3.9/:\(resourcePath)/lib/python3.9/site-packages:."
    putenv(python_path)
    
    // add PySwiftMpdules to Python's import list
    for mod in PythonSwiftImportList {
        print("Importing PySwiftModule:",String(cString: mod.0))
        if PyImport_AppendInittab(mod.0, mod.1) == -1 {
            PyErr_Print()
            fatalError()
        }
    }
    
    Py_Initialize()
    
    let _argc = Int(argc)
    let python_argv = PyMem_RawMalloc(MemoryLayout<UnicodeScalar>.size * _argc)!
    let _python_argv = python_argv.bindMemory(to: UnsafeMutablePointer<wchar_t>?.self, capacity: _argc)
    for i in 0..<_argc {
        _python_argv[i] = Py_DecodeLocale(argv[i], nil)
    }
    PySys_SetArgv(argc, _python_argv)
    
    //PyEval_InitThreads()
    
    load_custom_builtin_importer()
    
    let prog = Bundle.main.path(forResource: "YourApp/main", ofType: "pyc")!
    
    
    
    PyErr_Print()
    if let fd = fopen(prog, "r") {
        print("Running main.py: \(prog)")
        ret = PyRun_SimpleFileEx(fd, prog, 1)
        //ModuleFromMainPy(main_py_path, app_name: "MyApp")
        PyErr_Print()
        fclose(fd)
    } else {
        ret = 1;
        NSLog("Unable to open main.py, abort.")
    }
    
    
    
    
    
    Py_Finalize()
    
    exit(ret)
    
}


fileprivate func load_custom_builtin_importer() {
    let custom_builtin_importer = """
    import sys, imp, types
    from os import environ
    from os.path import exists, join
    try:
        # python 3
        import _imp
        EXTS = _imp.extension_suffixes()
        sys.modules['subprocess'] = types.ModuleType(name='subprocess')
        sys.modules['subprocess'].PIPE = None
        sys.modules['subprocess'].STDOUT = None
        sys.modules['subprocess'].DEVNULL = None
        sys.modules['subprocess'].CalledProcessError = Exception
        sys.modules['subprocess'].check_output = None
    except ImportError:
        EXTS = ['.so']
    # Fake redirection to supress console output
    if environ.get('KIVY_NO_CONSOLE', '0') == '1':
        class fakestd(object):
            def write(self, *args, **kw): pass
            def flush(self, *args, **kw): pass
        sys.stdout = fakestd()
        sys.stderr = fakestd()
    # Custom builtin importer for precompiled modules
    class CustomBuiltinImporter(object):
        def find_module(self, fullname, mpath=None):
            # print(f'find_module() fullname={fullname} mpath={mpath}')
            if '.' not in fullname:
                return
            if not mpath:
                return
            part = fullname.rsplit('.')[-1]
            for ext in EXTS:
               fn = join(list(mpath)[0], '{}{}'.format(part, ext))
               # print('find_module() {}'.format(fn))
               if exists(fn):
                   return self
            return
        def load_module(self, fullname):
            f = fullname.replace('.', '_')
            mod = sys.modules.get(f)
            if mod is None:
                # print('LOAD DYNAMIC', f, sys.modules.keys())
                try:
                    mod = imp.load_dynamic(f, f)
                except ImportError:
                    # import traceback; traceback.print_exc();
                    # print('LOAD DYNAMIC FALLBACK', fullname)
                    mod = imp.load_dynamic(fullname, fullname)
                sys.modules[fullname] = mod
                return mod
            return mod
    sys.meta_path.insert(0, CustomBuiltinImporter())
    """
    _ = custom_builtin_importer.withCString(PyRun_SimpleString)
}


