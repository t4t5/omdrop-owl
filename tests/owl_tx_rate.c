/* Exercise real OWL data frames, including fixed-radio TX_FLAGS alignment. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "tx.h"

static void frame(const char *text, int mcs, int bw40, int sgi) {
    const struct ether_addr self = {{2,0,0,0,0,1}}, peer = {{2,0,0,0,0,2}};
    struct awdl_state state = {0};
    struct ieee80211_state ieee = {0};
    uint8_t out[512], payload[] = {1,2,3};
    char formatted[64];
    assert(ieee80211_parse_tx_rate(text, &awdl_data_tx_rate) == 0);
    assert(awdl_data_tx_rate.mcs == mcs);
    assert(awdl_data_tx_rate.bw40 == bw40 && awdl_data_tx_rate.sgi == sgi);
    for (int fixed = 0; fixed <= 1; fixed++) {
        state.channel.fixed_radio = fixed;
        int len = awdl_init_full_data_frame(out, &self, &peer, payload, sizeof(payload), &state, &ieee);
        int rtlen = out[2] | out[3] << 8;
        unsigned present = out[4] | out[5] << 8 | out[6] << 16 | out[7] << 24;
        int offset = 8 + 2 * fixed;
        assert(len > rtlen && rtlen == offset + 3);
        assert(present == ((1u << 19) | (fixed ? 1u << 15 : 0)));
        if (fixed) assert(out[8] == 8 && out[9] == 0);
        assert(out[offset] == 7); /* BW, MCS and GI are all known. */
        assert(out[offset + 1] == (bw40 | sgi << 2));
        assert(out[offset + 2] == mcs);
        assert(!memcmp(out + len - sizeof(payload), payload, sizeof(payload)));
        ieee80211_format_tx_rate(formatted, sizeof(formatted), &awdl_data_tx_rate);
        printf("%s fixed=%d: %s; MCS bytes %02x %02x %02x\n", text, fixed, formatted,
               out[offset], out[offset + 1], out[offset + 2]);
    }
}

int main(void) {
    char text[32];
    for (int mcs = 0; mcs <= 15; mcs++) {
        snprintf(text, sizeof(text), "mcs%d", mcs);
        frame(text, mcs, 0, 0); /* as owl-01 sent it */
        for (int bw40 = 0; bw40 <= 1; bw40++) {
            snprintf(text, sizeof(text), "mcs%d-%d", mcs, bw40 ? 40 : 20);
            frame(text, mcs, bw40, 0);
            for (int sgi = 0; sgi <= 1; sgi++) {
                snprintf(text, sizeof(text), "mcs%d-%d-%s", mcs, bw40 ? 40 : 20, sgi ? "sgi" : "lgi");
                frame(text, mcs, bw40, sgi);
            }
        }
        snprintf(text, sizeof(text), "mcs%d-sgi", mcs);
        frame(text, mcs, 0, 1);
        snprintf(text, sizeof(text), "mcs%d-lgi", mcs);
        frame(text, mcs, 0, 0);
    }
    const char *bad[] = {"mcs", "mcs-1", "mcs16", "mcs7-80", "mcs7-40-junk", "mcs7-sgi-40", "mcs7-20-sgi-junk", "13", "54-sgi"};
    for (unsigned i = 0; i < sizeof(bad) / sizeof(bad[0]); i++)
        assert(ieee80211_parse_tx_rate(bad[i], &awdl_data_tx_rate) < 0);
    int legacy[] = {6,9,12,18,24,36,48,54};
    uint8_t out[32];
    for (unsigned i = 0; i < sizeof(legacy) / sizeof(legacy[0]); i++) {
        snprintf(text, sizeof(text), "%d", legacy[i]);
        assert(ieee80211_parse_tx_rate(text, &awdl_data_tx_rate) == 0);
        assert(ieee80211_init_radiotap_header_rate(out, &awdl_data_tx_rate) == 9);
        assert(out[4] == 4 && out[8] == legacy[i] * 2);
    }
    assert(ieee80211_init_radiotap_header(out) == 9 && out[8] == 24);
    puts("PASS: all HT MCS/width/GI combinations, NOACK alignment, invalid rates, legacy and action defaults");
    return 0;
}
