/* A MIF that ends in zero padding, as iPhones send, must be parsed and make
 * its sender a valid peer; a nonzero or truncated tail must still be refused
 * (patches/owl-09-action-zero-padding.patch). Built against OWL's sources
 * under AddressSanitizer by test_owl_padding.py. */
#include <stdio.h>
#include <string.h>

#include "rx.h"
#include "state.h"
#include "frame.h"
#include "version.h"

static const struct ether_addr self = {{0x02, 0x00, 0x00, 0x00, 0x00, 0x01}};
static const struct ether_addr peer = {{0x02, 0x00, 0x00, 0x00, 0x00, 0x02}};

/* An AWDL MIF carrying just a version TLV, which together with the MIF itself
 * is all a peer needs to be valid, followed by tail. */
static int mif(uint8_t *out, const uint8_t *tail, int tail_len) {
	struct awdl_action af = {
		.category = IEEE80211_VENDOR_SPECIFIC,
		.oui = AWDL_OUI,
		.type = AWDL_TYPE,
		.version = AWDL_VERSION_COMPAT,
		.subtype = AWDL_ACTION_MIF,
	};
	const uint8_t version[5] = {AWDL_VERSION_TLV, 2, 0, 0x34, AWDL_DEVCLASS_IOS};
	int off = 0;

	memcpy(out + off, &af, sizeof(af));
	off += sizeof(af);
	memcpy(out + off, version, sizeof(version));
	off += sizeof(version);
	memcpy(out + off, tail, tail_len);
	return off + tail_len;
}

/* Receives a MIF ending in tail from a new peer; 0 if the result and whether
 * the peer became valid are as expected. */
static int check(const char *what, const uint8_t *tail, int tail_len, int want_result) {
	struct awdl_state state;
	struct awdl_peer *p = NULL;
	uint8_t raw[64];
	const struct buf *frame;
	int result, valid;

	awdl_init_state(&state, "test", &self, CHAN_NULL, clock_time_us());
	state.filter_rssi = 0;
	frame = buf_new_const(raw, mif(raw, tail, tail_len));
	result = awdl_rx_action(frame, -40, clock_time_us(), &peer, &self, &state);
	awdl_peer_get(state.peers.peers, &peer, &p);
	valid = p && p->is_valid;
	buf_free(frame);
	awdl_peers_free(state.peers.peers);

	if (result != want_result || valid != (want_result == RX_OK)) {
		fprintf(stderr, "%s: result %d, peer %svalid; expected %d\n",
		        what, result, valid ? "" : "not ", want_result);
		return 1;
	}
	return 0;
}

int main(void) {
	static const uint8_t zeros[8] = {0};
	static const uint8_t nonzero[2] = {0, 1};
	static const uint8_t truncated[2] = {AWDL_VERSION_TLV, 2}; /* half a TLV header */
	int failed = 0;

	failed |= check("no padding", zeros, 0, RX_OK);
	failed |= check("1 zero", zeros, 1, RX_OK);
	failed |= check("2 zeros", zeros, 2, RX_OK);
	failed |= check("8 zeros", zeros, 8, RX_OK); /* as captured from an iPhone */
	failed |= check("nonzero tail", nonzero, 2, RX_UNEXPECTED_FORMAT);
	failed |= check("truncated TLV", truncated, 2, RX_UNEXPECTED_FORMAT);
	return failed;
}
