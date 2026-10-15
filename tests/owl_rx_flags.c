/* A received frame whose radiotap header has no Flags field must not be judged
 * by whatever the stack held where awdl_rx keeps them: an 0xff there reads as
 * "bad FCS" (patches/owl-13-rx-flags-init.patch). The frame is one of our own
 * MIFs, whose radiotap header (rate only) has no Flags. Built against OWL's
 * sources under AddressSanitizer by test_owl_rx_flags.py. */
#include <stdio.h>
#include <string.h>

#include "rx.h"
#include "state.h"
#include "tx.h"

static const struct ether_addr self = {{0x02, 0x00, 0x00, 0x00, 0x00, 0x01}};
static const struct ether_addr peer = {{0x02, 0x00, 0x00, 0x00, 0x00, 0x02}};

/* Leaves 0xff over the stack below the caller, where awdl_rx's locals go. */
static void __attribute__((noinline)) dirty_stack(void) {
	volatile uint8_t junk[16384];

	memset((void *) junk, 0xff, sizeof(junk));
}

int main(void) {
	struct awdl_state tx, rx;
	struct ieee80211_state ieee = {0};
	struct buf **data_frame = NULL, *data_end = NULL;
	uint8_t raw[512];
	const struct buf *frame;
	int len, result;

	awdl_init_state(&tx, "test", &peer, CHAN_NULL, clock_time_us());
	len = awdl_init_full_action_frame(raw, &tx, &ieee, AWDL_ACTION_MIF);
	awdl_init_state(&rx, "test", &self, CHAN_NULL, clock_time_us());
	rx.filter_rssi = 0;
	frame = buf_new_const(raw, len);
	dirty_stack();
	result = awdl_rx(frame, &data_frame, &data_end, &rx);
	buf_free(frame);
	awdl_peers_free(tx.peers.peers);
	awdl_peers_free(rx.peers.peers);

	if (result != RX_OK) {
		fprintf(stderr, "awdl_rx returned %d for a frame without radiotap Flags, expected %d\n", result, RX_OK);
		return 1;
	}
	return 0;
}
