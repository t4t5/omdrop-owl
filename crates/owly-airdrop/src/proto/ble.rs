//! The AirDrop BLE advertisement a sender transmits while browsing (§2).

/// Apple's Bluetooth company ID, the key of the manufacturer data.
pub const APPLE_COMPANY_ID: u16 = 0x004c;

/// The AirDrop TLV type in Apple's manufacturer data.
const AIRDROP_TYPE: u8 = 0x05;

/// The advertising interval current Apple devices answer to (BLE-5).
pub const INTERVAL_MS: u32 = 100;

/// The version 3 advert (BLE-2, BLE-5): a per-advert tag and the four
/// contact-hash prefixes, each the first 2 bytes of SHA-256 of an
/// identifier. How identifiers are normalized before hashing is open
/// (BLE-4), so nothing here computes them.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct Advert {
    pub tag: [u8; 3],
    /// The sender's contact hashes: the first 2 bytes of SHA-256 of its
    /// Apple ID, a phone number or an email address. A slot doesn't say
    /// which, since senders rotate them between advertisements (BLE-2).
    pub hashes: [[u8; 2]; 4],
}

impl Advert {
    /// BLE-3: a sender with no Apple identity sends zero hashes, which wakes
    /// Everyone-mode receivers. BLE-5 asks for a random `tag`.
    pub fn anonymous(tag: [u8; 3]) -> Self {
        Advert {
            tag,
            ..Self::default()
        }
    }

    /// The manufacturer data, without the company ID: the AirDrop TLV and
    /// its 18-byte payload (BLE-1, BLE-2).
    pub fn manufacturer_data(&self) -> Vec<u8> {
        let mut out = vec![AIRDROP_TYPE, 0x12, 0x40];
        out.extend_from_slice(&self.tag);
        out.extend_from_slice(&[0; 4]);
        out.push(0x03);
        for hash in self.hashes {
            out.extend_from_slice(&hash);
        }
        out.push(0x00);
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // spec: BLE-1, BLE-2, BLE-3, BLE-5
    #[test]
    fn anonymous_advert_layout() {
        let data = Advert::anonymous([0xa1, 0xb2, 0xc3]).manufacturer_data();
        assert_eq!(data.len(), 2 + 18);
        assert_eq!(&data[..2], &[0x05, 0x12]);
        assert_eq!(&data[2..6], &[0x40, 0xa1, 0xb2, 0xc3]);
        assert_eq!(&data[6..10], &[0; 4]);
        assert_eq!(data[10], 0x03);
        assert_eq!(&data[11..], &[0; 9]);
    }

    #[test]
    fn hashes_in_order() {
        let advert = Advert {
            tag: [0; 3],
            hashes: [[1, 2], [3, 4], [5, 6], [7, 8]],
        };
        assert_eq!(
            &advert.manufacturer_data()[11..],
            &[1, 2, 3, 4, 5, 6, 7, 8, 0]
        );
    }

    // The whole payload for another tag and zero hashes, spelled out.
    // spec: BLE-5
    #[test]
    fn anonymous_advert_bytes() {
        let tag = [0x12, 0x34, 0x56];
        let mut expected = vec![5, 18, 0x40];
        expected.extend(tag);
        expected.extend([0; 4]);
        expected.push(3);
        expected.extend([0; 8]);
        expected.push(0);
        assert_eq!(Advert::anonymous(tag).manufacturer_data(), expected);
    }
}
