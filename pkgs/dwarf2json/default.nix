{ lib, buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "dwarf2json";
  version = "0.8.0";

  src = fetchFromGitHub {
    owner = "volatilityfoundation";
    repo = "dwarf2json";
    rev = "9f14607e0d339d463ea725fbd5c08aa7b7d40f75";
    hash = "sha256-M5KKtn5kly23TwbjD5MVLzIum58exXqCFs6jxsg6oGM=";
  };

  vendorHash = "sha256-3PnXB8AfZtgmYEPJuh0fwvG38dtngoS/lxyx3H+rvFs=";

  meta = with lib; {
    description = "Converts DWARF symbols from Linux/macOS kernels into Volatility 3 ISF tables";
    homepage = "https://github.com/volatilityfoundation/dwarf2json";
    license = licenses.gpl3Only;
    maintainers = [ ];
    mainProgram = "dwarf2json";
  };
}
