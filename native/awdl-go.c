// SPDX-License-Identifier: GPL-3.0-or-later
/* AX211 secondary nl80211 GO context. No association/authentication server.
 * Build against installed Linux nl80211 UAPI and libnl3. */
#include <errno.h>
#include <limits.h>
#include <linux/nl80211.h>
#include <net/if.h>
#include <netlink/genl/ctrl.h>
#include <netlink/genl/genl.h>
#include <netlink/msg.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/prctl.h>
#include <time.h>
#include <unistd.h>

static uint8_t mac[6] = {2,0x25,0,0xaa,0,1};
static const char ssid[] = "DIRECT-omdrop";
static struct nl_sock *sk;
static int family;
static unsigned go_id, mon_id, phy_id;
static volatile sig_atomic_t stopping;
static void stop(int n) { (void)n; stopping = 1; }
static struct nl_msg *message(int cmd, unsigned id) {
    struct nl_msg *m = nlmsg_alloc();
    if (!m || !genlmsg_put(m,0,0,family,0,0,cmd,0)) abort();
    if (id && nla_put_u32(m, NL80211_ATTR_IFINDEX,id)) abort();
    return m;
}
static int submit(struct nl_msg *m) {
    int e = nl_send_auto(sk,m); nlmsg_free(m);
    if (e >= 0) e = nl_wait_for_ack(sk);
    if (e < 0) fprintf(stderr,"netlink: %s (%d)\n",nl_geterror(e),e);
    return e;
}
static int set_up(const char *name) {
    int fd = socket(AF_INET,SOCK_DGRAM|SOCK_CLOEXEC,0);
    struct ifreq r = {0}; snprintf(r.ifr_name,sizeof(r.ifr_name),"%s",name);
    if (fd < 0) return -1;
    int e = ioctl(fd,SIOCGIFFLAGS,&r);
    if (!e) { r.ifr_flags |= IFF_UP; e = ioctl(fd,SIOCSIFFLAGS,&r); }
    if (e) perror("interface up");
    close(fd); return e;
}
static int create(const char *name, unsigned type, unsigned *owned) {
    if (if_nametoindex(name)) { fprintf(stderr,"name collision: %s\n",name); return -1; }
    struct nl_msg *m = message(NL80211_CMD_NEW_INTERFACE,0);
    if (nla_put_u32(m,NL80211_ATTR_WIPHY,phy_id) ||
        nla_put_string(m,NL80211_ATTR_IFNAME,name) ||
        nla_put_u32(m,NL80211_ATTR_IFTYPE,type) ||
        nla_put(m,NL80211_ATTR_MAC,6,mac)) abort();
    if (submit(m) < 0) return -1;
    *owned = if_nametoindex(name);
    if (!*owned) return -1;
    return set_up(name);
}
static size_t beacon(uint8_t *b) {
    memset(b,0,256); b[0]=0x80; memset(b+4,0xff,6);
    memcpy(b+10,mac,6); memcpy(b+16,mac,6);
    b[32]=100; b[34]=0x21; b[35]=4; /* ESS, short preamble, short slot */
    size_t n=36; b[n++]=0; b[n++]=sizeof(ssid)-1;
    memcpy(b+n,ssid,sizeof(ssid)-1); n+=sizeof(ssid)-1;
    const uint8_t rates[]={1,8,0x8c,0x12,0x98,0x24,0xb0,0x48,0x60,0x6c};
    memcpy(b+n,rates,sizeof(rates)); n+=sizeof(rates);
    b[n++]=3; b[n++]=1; b[n++]=6;
    return n;
}
static size_t tail(uint8_t *b) {
    size_t n=0;
    b[n++]=45; b[n++]=26; memset(b+n,0,26);
    b[n+2]=0x1b; b[n+3]=0xff; n+=26; /* one-stream HT20, conservative caps */
    b[n++]=61; b[n++]=22; memset(b+n,0,22); b[n]=6; n+=22;
    const uint8_t p2p[]={221,18,0x50,0x6f,0x9a,9,2,2,0,0,1,3,6,0,2,0x25,0,0xaa,0,1};
    memcpy(b+n,p2p,sizeof(p2p)); memcpy(b+n+14,mac,6); n+=sizeof(p2p); return n;
}
static int start_ap(void) {
    uint8_t head[256], rest[128]; size_t hn=beacon(head),tn=tail(rest);
    const uint8_t basic[]={12,24,48};
    struct nl_msg *m=message(NL80211_CMD_START_AP,go_id);
    if (nla_put_u32(m,NL80211_ATTR_WIPHY_FREQ,2437) ||
        nla_put_u32(m,NL80211_ATTR_CHANNEL_WIDTH,NL80211_CHAN_WIDTH_20) ||
        nla_put_u32(m,NL80211_ATTR_CENTER_FREQ1,2437) ||
        nla_put_u32(m,NL80211_ATTR_BEACON_INTERVAL,100) ||
        nla_put_u32(m,NL80211_ATTR_DTIM_PERIOD,2) ||
        nla_put(m,NL80211_ATTR_SSID,sizeof(ssid)-1,ssid) ||
        nla_put_u32(m,NL80211_ATTR_HIDDEN_SSID,NL80211_HIDDEN_SSID_NOT_IN_USE) ||
        nla_put_u32(m,NL80211_ATTR_AUTH_TYPE,NL80211_AUTHTYPE_OPEN_SYSTEM) ||
        nla_put(m,NL80211_ATTR_BSS_BASIC_RATES,sizeof(basic),basic) ||
        nla_put_u8(m,NL80211_ATTR_AP_ISOLATE,1) ||
        nla_put(m,NL80211_ATTR_BEACON_HEAD,hn,head) ||
        nla_put(m,NL80211_ATTR_BEACON_TAIL,tn,rest)) abort();
    return submit(m);
}
static void remove_owned(const char *name,unsigned id) {
    if (!id || if_nametoindex(name)!=id) return;
    int fd=socket(AF_INET,SOCK_DGRAM|SOCK_CLOEXEC,0);
    struct ifreq r={0}; snprintf(r.ifr_name,sizeof(r.ifr_name),"%s",name);
    int ours=fd>=0 && !ioctl(fd,SIOCGIFHWADDR,&r) && !memcmp(r.ifr_hwaddr.sa_data,mac,6);
    if(fd>=0) close(fd);
    if(ours) submit(message(NL80211_CMD_DEL_INTERFACE,id));
    else fprintf(stderr,"not removing interface whose identity changed: %s\n",name);
}
static int self_test(void) {
    uint8_t h[256],t[128]; size_t hn=beacon(h),tn=tail(t),n=36;
    if (memcmp(h+10,mac,6)||memcmp(h+16,mac,6)) return 1;
    while(n<hn) { if(n+2>hn||n+2+h[n+1]>hn) return 1; n+=2+h[n+1]; }
    n=0; while(n<tn) { if(n+2>tn||n+2+t[n+1]>tn) return 1; n+=2+t[n+1]; }
    printf("beacon self-test passed: head=%zu tail=%zu BSSID=02:25:00:aa:00:01\n",hn,tn);
    return 0;
}
int main(int argc,char **argv) {
    if(argc==2&&!strcmp(argv[1],"--self-test")) return self_test();
    int have_phy=0,have_mac=0;
    for(int i=1;i<argc;i++) {
        if(!strcmp(argv[i],"--phy")&&i+1<argc) {
            char *end; const char *arg=argv[++i]; errno=0;
            unsigned long value=strtoul(arg,&end,10);
            if(!*arg||*arg=='-'||*end||errno||value>UINT_MAX) return 2;
            phy_id=(unsigned)value; have_phy=1;
        }
        else if(!strcmp(argv[i],"--mac")&&i+1<argc) {
            unsigned v[6]; char extra;
            if(sscanf(argv[++i],"%2x:%2x:%2x:%2x:%2x:%2x%c",&v[0],&v[1],&v[2],&v[3],&v[4],&v[5],&extra)!=6 ||
               strlen(argv[i])!=17 || (v[0]&3)!=2) return 2;
            for(int j=0;j<6;j++) mac[j]=(uint8_t)v[j];
            have_mac=1;
        } else { fprintf(stderr,"usage: %s --phy INDEX --mac LOCAL_MAC | --self-test\n",argv[0]); return 2; }
    }
    if(!have_phy||!have_mac) return 2;
    if(geteuid()) { fprintf(stderr,"requires root\n"); return 1; }
    signal(SIGINT,stop); signal(SIGTERM,stop); signal(SIGALRM,stop);
    pid_t parent=getppid();
    if(prctl(PR_SET_PDEATHSIG,SIGTERM)||getppid()!=parent) return 1;
    sk=nl_socket_alloc();
    if(!sk||genl_connect(sk)<0||(family=genl_ctrl_resolve(sk,"nl80211"))<0) return 1;
    struct timeval timeout={3,0};
    setsockopt(nl_socket_get_fd(sk),SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    int result=1;
    if(create("awdlgo0",NL80211_IFTYPE_P2P_GO,&go_id)<0||stopping) goto out;
    if(start_ap()<0||stopping) goto out;
    if(create("mon0",NL80211_IFTYPE_MONITOR,&mon_id)<0||stopping) goto out;
    printf("READY go=%u monitor=%u\n",go_id,mon_id); fflush(stdout);
    while(!stopping) { struct timespec delay={1,0}; nanosleep(&delay,NULL); }
    result=0;
out:
    remove_owned("mon0",mon_id);
    /* DEL_INTERFACE stops AP as well, and works after partial start failure. */
    remove_owned("awdlgo0",go_id);
    nl_socket_free(sk); return result;
}
