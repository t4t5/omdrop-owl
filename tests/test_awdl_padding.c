#include <stdio.h>
#include <string.h>
#include "state.h"
#include "frame.h"
#include "rx.h"
#include "peers.h"
#include "wire.h"

static int check(const char *label, const unsigned char *tail, int len, int expected) {
    struct awdl_state state;
    struct ether_addr self = {{2,0,0,0,0,1}}, peeraddr = {{2,0,0,0,0,2}};
    unsigned char data[32] = {0x7f,0,0x17,0xf2,8,0x10,3,0};
    struct awdl_action *action = (struct awdl_action *)data;
    action->type = AWDL_TYPE;
    action->version = AWDL_VERSION_COMPAT;
    /* Version and device class let a successfully parsed MIF validate a peer. */
    data[16]=21; data[17]=2; data[18]=0; data[19]=0x34; data[20]=1;
    memcpy(data+21,tail,len);
    awdl_init_state(&state,"test",&self,CHAN_NULL,1000);
    state.filter_rssi = 0;
    const struct buf *frame=buf_new_const(data,21+len);
    int result=awdl_rx_action(frame,-40,1000,&peeraddr,&self,&state);
    struct awdl_peer *peer=NULL;
    awdl_peer_get(state.peers.peers,&peeraddr,&peer);
    int valid=peer && peer->is_valid;
    int pass=(result==expected) && (valid==(expected==RX_OK));
    printf("%s: result=%d valid=%d %s\n",label,result,valid,pass?"PASS":"FAIL");
    buf_free(frame); awdl_peers_free(state.peers.peers);
    return !pass;
}
int main(void) {
    const unsigned char zero[]={0,0}, nonzero[]={0,1}, truncated[]={21,2};
    int errors=0;
    errors+=check("no padding",zero,0,RX_OK);
    errors+=check("one zero",zero,1,RX_OK);
    errors+=check("two zeros",zero,2,RX_OK);
    errors+=check("nonzero tail rejected",nonzero,2,RX_UNEXPECTED_FORMAT);
    errors+=check("truncated TLV rejected",truncated,2,RX_UNEXPECTED_FORMAT);
    return errors?1:0;
}
