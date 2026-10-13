/* An A-MSDU with more subframes than the receiver's array has slots must be
 * refused, not written past the array (patches/owl-08-amsdu-bound.patch).
 * Built against OWL's sources under AddressSanitizer by test_owl_amsdu.py:
 * an overflow aborts it. */
#include <stdio.h>
#include <string.h>

#include "rx.h"
#include "state.h"
#include "wire.h"
#include "ieee80211.h"

#define SLOTS 16
#define SUBFRAME_LEN 16 /* LLC/SNAP header and struct awdl_data, no payload */

static const struct ether_addr self = {{0x02, 0x00, 0x00, 0x00, 0x00, 0x01}};
static const struct ether_addr peer = {{0x02, 0x00, 0x00, 0x00, 0x00, 0x02}};

/* A QoS data frame from peer to self, behind an empty radiotap header,
 * carrying n minimal A-MSDU subframes. */
static int amsdu(uint8_t *out, int n) {
	static const uint8_t radiotap[8] = {0, 0, 8, 0, 0, 0, 0, 0};
	static const uint8_t llc_awdl[SUBFRAME_LEN] = {
		0xaa, 0xaa, 0x03, 0x00, 0x17, 0xf2, 0x08, 0x00, /* LLC/SNAP, AWDL */
		0x04, 0x03, 0x00, 0x00, 0x00, 0x00, 0x08, 0x00, /* struct awdl_data, IPv4 */
	};
	struct ieee80211_hdr hdr = {0};
	uint16_t qos = htole16(IEEE80211_QOS_CTL_A_MSDU_PRESENT);
	uint16_t len = htobe16(SUBFRAME_LEN);
	int off = 0;

	memcpy(out + off, radiotap, sizeof(radiotap));
	off += sizeof(radiotap);
	hdr.frame_control = htole16(IEEE80211_FTYPE_DATA | IEEE80211_STYPE_QOS_DATA);
	hdr.addr1 = self;
	hdr.addr2 = peer;
	memcpy(out + off, &hdr, sizeof(hdr));
	off += sizeof(hdr);
	memcpy(out + off, &qos, sizeof(qos));
	off += sizeof(qos);
	for (int i = 0; i < n; i++) {
		if (i > 0)
			off += (4 - ((14 + SUBFRAME_LEN) % 4)) % 4; /* padding */
		memcpy(out + off, &self, ETHER_ADDR_LEN);
		memcpy(out + off + 6, &peer, ETHER_ADDR_LEN);
		memcpy(out + off + 12, &len, sizeof(len));
		memcpy(out + off + 14, llc_awdl, SUBFRAME_LEN);
		off += 14 + SUBFRAME_LEN;
	}
	return off;
}

/* Receives n subframes into a SLOTS-slot array, as awdl_receive_frame does;
 * 0 if the result and the frames converted are as expected. */
static int check(struct awdl_state *state, int n, int want_result, int want_frames) {
	uint8_t raw[64 + 32 * (SLOTS + 8)];
	struct buf *data_arr[SLOTS];
	struct buf **data = &data_arr[0];
	const struct buf *frame = buf_new_const(raw, amsdu(raw, n));
	int result = awdl_rx(frame, &data, &data_arr[SLOTS], state);
	int frames = (int) (data - &data_arr[0]);

	for (struct buf **d = &data_arr[0]; d < data; d++)
		buf_free(*d);
	buf_free(frame);
	if (result != want_result || frames != want_frames) {
		fprintf(stderr, "%d subframes: result %d with %d frames, expected %d with %d\n",
		        n, result, frames, want_result, want_frames);
		return 1;
	}
	return 0;
}

int main(void) {
	struct awdl_state state;
	int failed = 0;

	awdl_init_state(&state, "test", &self, CHAN_OPCLASS_149, clock_time_us());
	awdl_peer_add(state.peers.peers, &peer, clock_time_us(), NULL, NULL);

	failed |= check(&state, 1, RX_OK, 1);
	failed |= check(&state, SLOTS, RX_OK, SLOTS);
	failed |= check(&state, SLOTS + 1, RX_TOO_MANY_FRAMES, SLOTS);
	failed |= check(&state, SLOTS + 8, RX_TOO_MANY_FRAMES, SLOTS);
	awdl_peers_free(state.peers.peers);
	return failed;
}
