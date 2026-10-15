/* A PSF carries the HT capabilities TLV as a MIF does (Android's AWDL drops a
 * PSF without it), and only a MIF carries the ARPA TLV
 * (patches/owl-12-psf-ht-capabilities.patch). Built against OWL's sources
 * under AddressSanitizer by test_owl_ht_caps.py. */
#include <stdio.h>
#include <string.h>

#include "tx.h"

static const struct ether_addr self = {{0x02, 0x00, 0x00, 0x00, 0x00, 0x01}};

/* The HT capabilities value an iPad sends. */
static const uint8_t ht[] = {0x00, 0x00, 0xce, 0x11, 0x1b, 0xff, 0x00, 0x00};

/* Builds a frame of this type and walks its TLVs: 0 if exactly one is the HT
 * capabilities (type 7) with the value above, an ARPA TLV (type 16) is there
 * only if want_arpa, and the TLVs fill the frame exactly. */
static int check(const char *what, enum awdl_action_type type, int want_arpa) {
	struct awdl_state state;
	struct ieee80211_state ieee = {0};
	uint8_t frame[512], scratch[128];
	int off, len, n_ht = 0, bad_ht = 0, arpa = 0;

	awdl_init_state(&state, "test", &self, CHAN_NULL, clock_time_us());
	len = awdl_init_full_action_frame(frame, &state, &ieee, type);
	off = ieee80211_init_radiotap_header(scratch)
	    + ieee80211_init_awdl_action_hdr(scratch, &self, &state.dst, &ieee)
	    + awdl_init_action(scratch, type);
	while (off + (int) sizeof(struct tl) <= len) {
		const struct tl *tl = (const struct tl *) (frame + off);
		if (tl->type == AWDL_ENHANCED_DATA_RATE_CAPABILITIES_TLV) {
			n_ht++;
			bad_ht |= tl->length != sizeof(ht) || memcmp(frame + off + sizeof(struct tl), ht, sizeof(ht));
		}
		arpa += tl->type == AWDL_ARPA_TLV;
		off += sizeof(struct tl) + tl->length;
	}
	awdl_peers_free(state.peers.peers);
	if (n_ht != 1 || bad_ht || arpa != want_arpa || off != len) {
		fprintf(stderr, "%s: %d HT TLVs (%s), %d ARPA TLVs, parsed to %d of %d\n",
		        what, n_ht, bad_ht ? "wrong value" : "right value", arpa, off, len);
		return 1;
	}
	return 0;
}

int main(void) {
	int failed = 0;

	failed |= check("PSF", AWDL_ACTION_PSF, 0);
	failed |= check("MIF", AWDL_ACTION_MIF, 1);
	return failed;
}
