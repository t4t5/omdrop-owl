# omdrop-owl: the radio half of omdrop on MediaTek MT7925 Wi-Fi, through OWL.
#
# Build from a checkout of this repository:  makepkg -si
pkgname=omdrop-owl
pkgver=0.1.0
pkgrel=1
pkgdesc="AirDrop radio backend for omdrop on MediaTek MT7925 Wi-Fi: AWDL in userspace through OWL"
arch=('x86_64' 'aarch64')
url="https://github.com/t4t5/omdrop-owl"
# OWL (and our patches to it) GPL-3.0-or-later; its bundled radiotap parser
# ISC; omdrop-awdl's tools GPL-2.0-only. They ship as separate programs.
license=('GPL-3.0-or-later' 'GPL-2.0-only' 'ISC')
depends=('bash' 'python' 'iproute2' 'iputils' 'iw' 'polkit' 'util-linux' 'procps-ng'
         'libpcap' 'libev' 'libnl' 'networkmanager' 'keyutils'
         'python-libarchive-c' 'python-pillow' 'python-zeroconf' 'python-ifaddr'
         'bluez' 'python-dbus' 'python-gobject')
makedepends=('git' 'cmake' 'gcc')
# Both own /usr/lib/omdrop: one radio backend at a time.
conflicts=('brcmfmac-awdl-dkms')
install="${pkgname}.install"

# Keep in step with ./pins (prepare() checks).
_owl_commit=832d70f815c3d4a06a02117bf0fc5e868daa1ff0
_omdrop_awdl_commit=534f91a525337951ca19c311e53d333bd6d55100
source=("owl::git+https://github.com/jedbillyb/owl.git#commit=${_owl_commit}"
        "googletest::git+https://github.com/google/googletest.git"
        "radiotap::git+https://github.com/radiotap/radiotap-library.git"
        "omdrop-awdl::git+https://github.com/brentkearney/omdrop-awdl.git#commit=${_omdrop_awdl_commit}")
sha256sums=('SKIP' 'SKIP' 'SKIP' 'SKIP')

# omdrop-awdl's radio-independent tools, installed unmodified beside our
# helper: send-to-peer finds the helper, the sender and the BLE advertiser
# next to itself.
_from_omdrop_awdl=(send-to-peer airdrop-send.py awdl-af-parse.py awdl_identity.py
                   awdl_debug.py ble-airdrop-adv.py awdl-airdrop-adv.py awdl-mdns-respond.py)

prepare() {
  . "${startdir}/pins"
  [[ "$OWL_COMMIT" == "$_owl_commit" && "$OMDROP_AWDL_COMMIT" == "$_omdrop_awdl_commit" ]] \
    || { error "PKGBUILD's pinned commits differ from ./pins"; return 1; }

  # OWL's submodules, at the commits it records, from the clones makepkg made.
  cd "${srcdir}/owl"
  git submodule init
  git config submodule.googletest.url "${srcdir}/googletest"
  git config submodule.radiotap.url "${srcdir}/radiotap"
  git -c protocol.file.allow=always submodule update

  local p
  for p in "${startdir}"/patches/owl-*.patch; do
    msg2 "applying ${p##*/}"
    git apply "$p"
  done
}

build() {
  # The policy minimum is for the bundled googletest, whose
  # cmake_minimum_required predates 3.5, which CMake 4 refuses. Only the owl
  # target is built: googletest fails under current GCC and isn't needed.
  cmake -S owl -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -Wno-dev
  cmake --build build --target owl
}

check() {
  case "$(build/daemon/owl -S intersect -R 12 -m 02:00:00:00:00:01 -h 2>&1 || true)" in
    *"invalid option"*|*"-R takes"*|*"-m takes"*) error "owl lacks -S, -R or -m: the patches did not apply"; return 1 ;;
  esac
}

package() {
  local lib="${pkgdir}/usr/lib/omdrop" f
  install -Dm755 "${startdir}/userspace/omdrop-discoverable" "${lib}/omdrop-discoverable"
  install -Dm755 build/daemon/owl "${lib}/owl"
  for f in "${_from_omdrop_awdl[@]}"; do
    install -Dm755 "omdrop-awdl/userspace/${f}" "${lib}/${f}"
  done
  install -Dm644 "${startdir}/packaging/omdrop-owl.policy" \
    "${pkgdir}/usr/share/polkit-1/actions/io.github.t4t5.omdrop-owl.policy"
  install -Dm644 "${startdir}/packaging/99-omdrop-owl-unmanaged.conf" \
    "${pkgdir}/usr/lib/NetworkManager/conf.d/99-omdrop-owl-unmanaged.conf"
  install -Dm644 "${startdir}/README.md" "${pkgdir}/usr/share/doc/${pkgname}/README.md"
  install -Dm644 owl/COPYING "${pkgdir}/usr/share/licenses/${pkgname}/OWL-GPL-3.0"
  install -Dm644 omdrop-awdl/LICENSE "${pkgdir}/usr/share/licenses/${pkgname}/omdrop-awdl-LICENSE"
  install -Dm644 owl/radiotap/COPYING "${pkgdir}/usr/share/licenses/${pkgname}/radiotap-ISC"
}
