/* owl -V makes a MIF advertise two streams and VHT: the HT capabilities TLV
 * grows from 8 bytes to the 9 an iPad sends, and a VHT capabilities element
 * follows it. Without -V the frame is as before (patches/owl-14-wide.patch).
 * Built against OWL's sources under AddressSanitizer by test_owl_wide.py. */
#include <stdio.h>
#include <string.h>

#include "tx.h"

static const struct ether_addr self = {{0x02, 0x00, 0x00, 0x00, 0x00, 0x01}};

static const uint8_t ht_one[] = {0x00, 0x00, 0xce, 0x11, 0x1b, 0xff, 0x00, 0x00};
static const uint8_t ht_two[] = {0x00, 0x00, 0xce, 0x11, 0x1b, 0xff, 0xff, 0x00, 0x00};
/* An IEEE 802.11 container holding a VHT capabilities element (id 191, 12 bytes). */
static const uint8_t vht[] = {191, 12, 0x30, 0x01, 0x80, 0x03, 0xfa, 0xff, 0x00, 0x00, 0xfa, 0xff, 0x00, 0x00};

/* Builds a MIF and walks its TLVs: 0 if exactly one is the HT capabilities
 * (type 7) with want_ht, a container TLV (type 17) with the VHT element is
 * there only with -V, and the TLVs fill the frame exactly. */
static int check(const char *what, int wide, const uint8_t *want_ht, int ht_len) {
	struct awdl_state state;
	struct ieee80211_state ieee = {0};
	uint8_t frame[512], scratch[128];
	int off, len, n_ht = 0, bad_ht = 0, n_vht = 0, bad_vht = 0;

	awdl_wide = wide;
	awdl_init_state(&state, "test", &self, CHAN_NULL, clock_time_us());
	len = awdl_init_full_action_frame(frame, &state, &ieee, AWDL_ACTION_MIF);
	off = ieee80211_init_radiotap_header(scratch)
	    + ieee80211_init_awdl_action_hdr(scratch, &self, &state.dst, &ieee)
	    + awdl_init_action(scratch, AWDL_ACTION_MIF);
	while (off + (int) sizeof(struct tl) <= len) {
		const struct tl *tl = (const struct tl *) (frame + off);
		const uint8_t *value = frame + off + sizeof(struct tl);
		if (tl->type == AWDL_ENHANCED_DATA_RATE_CAPABILITIES_TLV) {
			n_ht++;
			bad_ht |= tl->length != ht_len || memcmp(value, want_ht, ht_len);
		}
		if (tl->type == AWDL_IEEE80211_CNTNR_TLV) {
			n_vht++;
			bad_vht |= tl->length != sizeof(vht) || memcmp(value, vht, sizeof(vht));
		}
		off += sizeof(struct tl) + tl->length;
	}
	awdl_peers_free(state.peers.peers);
	if (n_ht != 1 || bad_ht || n_vht != wide || bad_vht || off != len) {
		fprintf(stderr, "%s: %d HT TLVs (%s), %d VHT (%s), parsed to %d of %d\n", what,
		        n_ht, bad_ht ? "wrong value" : "right value",
		        n_vht, bad_vht ? "wrong value" : "right value", off, len);
		return 1;
	}
	return 0;
}

int main(void) {
	int failed = 0;

	failed |= check("without -V", 0, ht_one, sizeof(ht_one));
	failed |= check("with -V", 1, ht_two, sizeof(ht_two));
	return failed;
}
