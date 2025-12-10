{ pkgs, lib, python3Packages ? pkgs.python311Packages }:

let
    generateRequirements = requirements:
        "[${lib.concatMapStringsSep ", " (req: "'${req}'") requirements}]";

    generatePreBuild = { name, description, version, requirementsList }: 
    let
        pythonModuleName = lib.replaceStrings ["-"] ["_"] name;
    in
    ''
        mkdir -p src/
        touch src/__init__.py

        cp ${name}.py src/${pythonModuleName}.py

        cat > setup.py << EOF
from setuptools import setup, find_packages

setup(
    name='${name}',
    version='${version}',
    description='${description}',
    packages=find_packages('.'),
    install_requires=${generateRequirements requirementsList},
    entry_points={
        'console_scripts': [
        '${name}=src.${pythonModuleName}:main',
        ],
    },
)
EOF
    '';

    createPythonPackage = { name, version, description, src, requirements }: 
    let
        requirementsList = lib.filter (name: name != "") (lib.splitString "\n" requirements);
        propagatedBuildInputs = map (name: python3Packages.${name}) requirementsList;
    in rec {
        package = python3Packages.buildPythonPackage {
            pname = name;

            inherit version description src propagatedBuildInputs;

            preBuild = generatePreBuild {
                inherit name description version requirementsList;
            };

            format = "setuptools";

            doCheck = false;

            meta = with lib; {
                inherit description;
            };
        };

        wrapper = pkgs.writeShellScriptBin name ''
            #!${pkgs.stdenv.shell}
            exec ${package}/bin/${name} "$@"
        '';
    };
in
let
    workspaceNames = createPythonPackage {
        name = "i3-workspace-names-daemon";
        version = "0.0.1";
        description = "Python script to auto-rename workspaces based on content";
        src = ./scripts;
        requirements = "i3ipc";
    };
in
{
    # To add a new python script add a call to createPythonPackage where the name
    # matches a .py file without the suffix in the directory specified by src. Any
    # dependencies can be specified in the requirements which is a newline delimited
    # list of python packages (note: their names need to be the same in pypi and nix)
    workspaceNames = workspaceNames.wrapper;
}


