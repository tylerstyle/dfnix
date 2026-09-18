{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "dwarf2json";
  version = "0.8.0";

  src = fetchFromGitHub {
    owner = "volatilityfoundation";
    repo = "dwarf2json";
    rev = "4ee603f9dc0f6e165b4cbf4dffb45d064cfcb3ee";
    hash = "sha256-4O5L3c6bI4U417n5M9JmU6aW3yqI1bKz0VvWq8w0mK0=";
  };

  vendorHash = null;

  meta = with lib; {
    description = "Converts DWARF symbols from Linux/macOS kernels into Volatility 3 ISF tables";
    homepage = "https://github.com/volatilityfoundation/dwarf2json";
    license = licenses.gpl3Only;
    maintainers = [ ];
    mainProgram = "dwarf2json";
  };
}
