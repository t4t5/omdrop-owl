/* A Samsung Galaxy S24's AirDrop port comes from the SRV record in the Service
 * Response TLV of its MIFs, and OWL logs it once per change
 * (patches/owl-14-airdrop-port.patch). Anything else in that TLV must leave
 * the frame, and the peer, as they were. Built against OWL's sources under
 * AddressSanitizer by test_owl_airdrop_port.py. */
#include <stdio.h>
#include <string.h>

#include "rx.h"
#include "state.h"
#include "frame.h"
#include "log.h"
#include "version.h"

/* A MIF from an S24 in Quick Share's AirDrop mode, from its AWDL address
 * 7a:c1:d0:ea:9f:1e, as captured on 2026-10-13 (the body after the 802.11
 * header). Its SRV record, in 4ef69900f998._airdrop._tcp.local's compressed
 * name (0xc009 "_airdrop", "_tcp", 0xc00c "local"), says port 35529. */
static const uint8_t s24_mif[] = {
	0x7f, 0x00, 0x17, 0xf2, 0x08, 0x10, 0x03, 0x00, 0x7e, 0xed, 0x12, 0x00,
	0x7e, 0xed, 0x12, 0x00, 0x04, 0x49, 0x00, 0x2c, 0x15, 0x00, 0x2c, 0x00,
	0x10, 0x00, 0x6e, 0x00, 0x00, 0x18, 0x10, 0x00, 0x10, 0x00, 0x05, 0x00,
	0x03, 0x03, 0x03, 0x03, 0x1c, 0xce, 0x51, 0x4f, 0x2c, 0x87, 0x04, 0x00,
	0x8a, 0x01, 0x00, 0x00, 0x0f, 0x03, 0x00, 0x03, 0xff, 0xff, 0x2c, 0x80,
	0x2c, 0x80, 0x2c, 0x80, 0x2c, 0x80, 0x2c, 0x80, 0x2c, 0x80, 0x2c, 0x80,
	0x2c, 0x80, 0x2c, 0x80, 0x2c, 0x80, 0x2c, 0x80, 0x2c, 0x80, 0x2c, 0x80,
	0x2c, 0x80, 0x2c, 0x80, 0x2c, 0x80, 0x00, 0x00, 0x05, 0x15, 0x00, 0x00,
	0x00, 0x00, 0x01, 0x00, 0x1c, 0xce, 0x51, 0x4f, 0x2c, 0x87, 0x3c, 0x00,
	0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x12, 0x29, 0x00, 0x0f,
	0x03, 0x00, 0x03, 0xff, 0xff, 0x2c, 0x80, 0x2c, 0x80, 0x2c, 0x80, 0x2c,
	0x80, 0x2c, 0x80, 0x2c, 0x80, 0x2c, 0x80, 0x2c, 0x80, 0x2c, 0x80, 0x2c,
	0x80, 0x2c, 0x80, 0x2c, 0x80, 0x2c, 0x80, 0x2c, 0x80, 0x2c, 0x80, 0x2c,
	0x80, 0x00, 0x00, 0x00, 0x18, 0x28, 0x00, 0x1c, 0xce, 0x51, 0x4f, 0x2c,
	0x87, 0x1c, 0xce, 0x51, 0x4f, 0x2c, 0x87, 0x00, 0x00, 0x00, 0x00, 0x01,
	0x00, 0x00, 0x00, 0x3c, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0c,
	0x0f, 0x00, 0x24, 0x8f, 0x54, 0x52, 0x00, 0x02, 0x00, 0x7a, 0xc1, 0xd0,
	0xea, 0x9f, 0x1e, 0x00, 0x00, 0x07, 0x09, 0x00, 0x00, 0x00, 0x6f, 0x00,
	0x17, 0xff, 0xff, 0x00, 0x00, 0x11, 0x0e, 0x00, 0xbf, 0x0c, 0x36, 0x00,
	0x80, 0x0f, 0xfa, 0xff, 0x00, 0x00, 0xfa, 0xff, 0x00, 0x00, 0x15, 0x02,
	0x00, 0x34, 0x02, 0x06, 0x09, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x02, 0x1d, 0x00, 0x0a, 0x00, 0xc0, 0x09, 0x04, 0x5f,
	0x74, 0x63, 0x70, 0xc0, 0x0c, 0x0c, 0x0d, 0x00, 0x00, 0x00, 0x0c, 0x34,
	0x65, 0x66, 0x36, 0x39, 0x39, 0x30, 0x30, 0x66, 0x39, 0x39, 0x38, 0x02,
	0x36, 0x00, 0x17, 0x00, 0x0c, 0x34, 0x65, 0x66, 0x36, 0x39, 0x39, 0x30,
	0x30, 0x66, 0x39, 0x39, 0x38, 0xc0, 0x09, 0x04, 0x5f, 0x74, 0x63, 0x70,
	0xc0, 0x0c, 0x21, 0x19, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x8a,
	0xc9, 0x10, 0x41, 0x6e, 0x64, 0x72, 0x6f, 0x69, 0x64, 0x5f, 0x4b, 0x42,
	0x41, 0x4f, 0x33, 0x4f, 0x38, 0x5a, 0xc0, 0x0c, 0x02, 0x27, 0x00, 0x17,
	0x00, 0x0c, 0x34, 0x65, 0x66, 0x36, 0x39, 0x39, 0x30, 0x30, 0x66, 0x39,
	0x39, 0x38, 0xc0, 0x09, 0x04, 0x5f, 0x74, 0x63, 0x70, 0xc0, 0x0c, 0x10,
	0x0a, 0x00, 0x00, 0x00, 0x09, 0x66, 0x6c, 0x61, 0x67, 0x73, 0x3d, 0x34,
	0x38, 0x39
};
static const struct ether_addr s24 = {{0x7a, 0xc1, 0xd0, 0xea, 0x9f, 0x1e}};

static const struct ether_addr self = {{0x02, 0x00, 0x00, 0x00, 0x00, 0x01}};
static const struct ether_addr peer = {{0x02, 0x00, 0x00, 0x00, 0x00, 0x02}};

static struct awdl_state state;
static FILE *log_out;

static void start(void) {
	awdl_init_state(&state, "test", &self, CHAN_NULL, clock_time_us());
	state.filter_rssi = 0;
	log_out = tmpfile();
	log_set_fp(log_out);
	log_set_quiet(1);
	log_set_level(LOG_INFO);
}

static void stop(void) {
	awdl_peers_free(state.peers.peers);
	fclose(log_out);
}

static int rx(const struct ether_addr *from, const uint8_t *body, int len) {
	const struct buf *frame = buf_new_const(body, len);
	int result = awdl_rx_action(frame, -40, clock_time_us(), from, &self, &state);
	buf_free(frame);
	return result;
}

static int port_of(const struct ether_addr *from) {
	struct awdl_peer *p = NULL;
	awdl_peer_get(state.peers.peers, from, &p);
	return p ? p->airdrop_port : -1;
}

static int logged(void) {
	char text[4096];
	int n = 0;
	size_t len;
	const char *at;

	rewind(log_out);
	len = fread(text, 1, sizeof(text) - 1, log_out);
	text[len] = 0;
	for (at = text; (at = strstr(at, "airdrop port")); at++)
		n++;
	fseek(log_out, 0, SEEK_END);
	return n;
}

/* A MIF with just a version TLV, which makes the peer valid, then tail. */
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

/* A Service Response TLV: a record of the given name and type whose data is
 * priority, weight, port and the target label "t". */
static int service(uint8_t *out, const uint8_t *name, int name_len, uint8_t type, uint16_t port) {
	const uint8_t target[2] = {1, 't'};
	int value = 2 + name_len + 1 + 2 + 2 + 6 + sizeof(target), off = 0;

	out[off++] = AWDL_SERVICE_RESPONSE_TLV;
	out[off++] = value & 0xff;
	out[off++] = value >> 8;
	out[off++] = (name_len + 1) & 0xff;
	out[off++] = (name_len + 1) >> 8;
	memcpy(out + off, name, name_len);
	off += name_len;
	out[off++] = type;
	out[off++] = (6 + sizeof(target)) & 0xff;
	out[off++] = 0;
	out[off++] = 0; /* two bytes before the record */
	out[off++] = 0;
	memset(out + off, 0, 4); /* priority, weight */
	off += 4;
	out[off++] = port >> 8;
	out[off++] = port & 0xff;
	memcpy(out + off, target, sizeof(target));
	return off + sizeof(target);
}

/* Receives a MIF with this record from a new peer: 0 if the frame is accepted
 * and the peer ends up with want_port. */
static int check(const char *what, const uint8_t *name, int name_len, uint8_t type, uint16_t port, int want_port) {
	uint8_t tlv[128], raw[192];
	int result, got, failed = 0;

	start();
	result = rx(&peer, raw, mif(raw, tlv, service(tlv, name, name_len, type, port)));
	got = port_of(&peer);
	if (result != RX_OK || got != want_port || logged() != (want_port > 0)) {
		fprintf(stderr, "%s: result %d, port %d, %d log lines; expected %d, port %d\n",
		        what, result, got, logged(), RX_OK, want_port);
		failed = 1;
	}
	stop();
	return failed;
}

/* The real thing: the port, and one log line however often it is repeated. */
static int check_s24(void) {
	int failed = 0;

	start();
	if (rx(&s24, s24_mif, sizeof(s24_mif)) != RX_OK || port_of(&s24) != 35529 || logged() != 1) {
		fprintf(stderr, "s24 MIF: port %d, %d log lines; expected 35529, 1\n", port_of(&s24), logged());
		failed = 1;
	}
	rx(&s24, s24_mif, sizeof(s24_mif));
	if (logged() != 1) {
		fprintf(stderr, "s24 MIF again: %d log lines; expected 1\n", logged());
		failed = 1;
	}
	stop();
	return failed;
}

/* A new port is logged again and replaces the old one. */
static int check_change(void) {
	static const uint8_t name[] = {1, 'a', 0xc0, 0x07};
	uint8_t tlv[128], raw[192];
	int failed = 0;

	start();
	rx(&peer, raw, mif(raw, tlv, service(tlv, name, sizeof(name), 33, 40000)));
	rx(&peer, raw, mif(raw, tlv, service(tlv, name, sizeof(name), 33, 40001)));
	if (port_of(&peer) != 40001 || logged() != 2) {
		fprintf(stderr, "changed port: %d, %d log lines; expected 40001, 2\n", port_of(&peer), logged());
		failed = 1;
	}
	stop();
	return failed;
}

int main(void) {
	/* 0xc007 is "_airdrop._tcp.local" whole; 0xc009 + "_tcp" + 0xc00c is how the S24 spells it */
	static const uint8_t whole[] = {1, 'a', 0xc0, 0x07};
	static const uint8_t mixed[] = {1, 'a', 0xc0, 0x09, 4, '_', 't', 'c', 'p', 0xc0, 0x0c};
	static const uint8_t literal[] = {1, 'a', 8, '_', 'a', 'i', 'r', 'd', 'r', 'o', 'p',
	                                  4, '_', 't', 'c', 'p', 5, 'l', 'o', 'c', 'a', 'l'};
	static const uint8_t airplay[] = {1, 'a', 0xc0, 0x01};
	static const uint8_t no_instance[] = {0xc0, 0x07};
	static const uint8_t unknown_code[] = {1, 'a', 0xc0, 0x7f};
	static const uint8_t label_past_end[] = {1, 'a', 20, '_'};
	int failed = 0;

	failed |= check_s24();
	failed |= check_change();
	failed |= check("whole code", whole, sizeof(whole), 33, 40000, 40000);
	failed |= check("codes mid-name", mixed, sizeof(mixed), 33, 40000, 40000);
	failed |= check("no codes", literal, sizeof(literal), 33, 40000, 40000);
	failed |= check("port 8770, as Apple publishes", whole, sizeof(whole), 33, 8770, 8770);
	failed |= check("another service", airplay, sizeof(airplay), 33, 40000, 0);
	failed |= check("a PTR record", whole, sizeof(whole), 12, 40000, 0);
	failed |= check("no instance", no_instance, sizeof(no_instance), 33, 40000, 0);
	failed |= check("port 0", whole, sizeof(whole), 33, 0, 0);
	failed |= check("unknown code", unknown_code, sizeof(unknown_code), 33, 40000, 0);
	failed |= check("label past the end", label_past_end, sizeof(label_past_end), 33, 40000, 0);
	return failed;
}
