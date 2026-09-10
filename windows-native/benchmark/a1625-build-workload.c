#include <stdint.h>
#include <stdio.h>

typedef uint64_t (*fn_t)(uint64_t);

static uint64_t f000(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 5;
        x *= UINT64_C(11400714819323198485);
        x ^= x << 3;
        x += UINT64_C(15485907386658061715) + i;
    }
    return x;
}
static uint64_t f001(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 6;
        x *= UINT64_C(11400715918834826696);
        x ^= x << 4;
        x += UINT64_C(15485907386658022308) + i;
    }
    return x;
}
static uint64_t f002(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 7;
        x *= UINT64_C(11400717018346454907);
        x ^= x << 5;
        x += UINT64_C(15485907386657980925) + i;
    }
    return x;
}
static uint64_t f003(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 8;
        x *= UINT64_C(11400718117858083118);
        x ^= x << 6;
        x += UINT64_C(15485907386657941302) + i;
    }
    return x;
}
static uint64_t f004(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 9;
        x *= UINT64_C(11400719217369711329);
        x ^= x << 7;
        x += UINT64_C(15485907386658161999) + i;
    }
    return x;
}
static uint64_t f005(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 10;
        x *= UINT64_C(11400720316881339540);
        x ^= x << 8;
        x += UINT64_C(15485907386658122368) + i;
    }
    return x;
}
static uint64_t f006(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 11;
        x *= UINT64_C(11400721416392967751);
        x ^= x << 9;
        x += UINT64_C(15485907386658080985) + i;
    }
    return x;
}
static uint64_t f007(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 12;
        x *= UINT64_C(11400722515904595962);
        x ^= x << 10;
        x += UINT64_C(15485907386658303506) + i;
    }
    return x;
}
static uint64_t f008(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 13;
        x *= UINT64_C(11400723615416224173);
        x ^= x << 11;
        x += UINT64_C(15485907386658262059) + i;
    }
    return x;
}
static uint64_t f009(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 14;
        x *= UINT64_C(11400724714927852384);
        x ^= x << 12;
        x += UINT64_C(15485907386658222716) + i;
    }
    return x;
}
static uint64_t f010(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 15;
        x *= UINT64_C(11400725814439480595);
        x ^= x << 13;
        x += UINT64_C(15485907386658444213) + i;
    }
    return x;
}
static uint64_t f011(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 16;
        x *= UINT64_C(11400726913951108806);
        x ^= x << 14;
        x += UINT64_C(15485907386658402766) + i;
    }
    return x;
}
static uint64_t f012(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 17;
        x *= UINT64_C(11400728013462737017);
        x ^= x << 15;
        x += UINT64_C(15485907386658363143) + i;
    }
    return x;
}
static uint64_t f013(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 18;
        x *= UINT64_C(11400729112974365228);
        x ^= x << 3;
        x += UINT64_C(15485907386657535320) + i;
    }
    return x;
}
static uint64_t f014(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 19;
        x *= UINT64_C(11400730212485993439);
        x ^= x << 4;
        x += UINT64_C(15485907386657495697) + i;
    }
    return x;
}
static uint64_t f015(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 20;
        x *= UINT64_C(11400731311997621650);
        x ^= x << 5;
        x += UINT64_C(15485907386657454250) + i;
    }
    return x;
}
static uint64_t f016(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 21;
        x *= UINT64_C(11400732411509249861);
        x ^= x << 6;
        x += UINT64_C(15485907386657414883) + i;
    }
    return x;
}
static uint64_t f017(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 5;
        x *= UINT64_C(11400733511020878072);
        x ^= x << 7;
        x += UINT64_C(15485907386657635380) + i;
    }
    return x;
}
static uint64_t f018(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 6;
        x *= UINT64_C(11400734610532506283);
        x ^= x << 8;
        x += UINT64_C(15485907386657595981) + i;
    }
    return x;
}
static uint64_t f019(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 7;
        x *= UINT64_C(11400735710044134494);
        x ^= x << 9;
        x += UINT64_C(15485907386657555334) + i;
    }
    return x;
}
static uint64_t f020(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 8;
        x *= UINT64_C(11400736809555762705);
        x ^= x << 10;
        x += UINT64_C(15485907386657776095) + i;
    }
    return x;
}
static uint64_t f021(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 9;
        x *= UINT64_C(11400737909067390916);
        x ^= x << 11;
        x += UINT64_C(15485907386657736464) + i;
    }
    return x;
}
static uint64_t f022(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 10;
        x *= UINT64_C(11400739008579019127);
        x ^= x << 12;
        x += UINT64_C(15485907386657695017) + i;
    }
    return x;
}
static uint64_t f023(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 11;
        x *= UINT64_C(11400740108090647338);
        x ^= x << 13;
        x += UINT64_C(15485907386657917794) + i;
    }
    return x;
}
static uint64_t f024(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 12;
        x *= UINT64_C(11400741207602275549);
        x ^= x << 14;
        x += UINT64_C(15485907386657876155) + i;
    }
    return x;
}
static uint64_t f025(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 13;
        x *= UINT64_C(11400742307113903760);
        x ^= x << 15;
        x += UINT64_C(15485907386657836748) + i;
    }
    return x;
}
static uint64_t f026(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 14;
        x *= UINT64_C(11400743406625531971);
        x ^= x << 3;
        x += UINT64_C(15485907386657008645) + i;
    }
    return x;
}
static uint64_t f027(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 15;
        x *= UINT64_C(11400744506137160182);
        x ^= x << 4;
        x += UINT64_C(15485907386656969310) + i;
    }
    return x;
}
static uint64_t f028(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 16;
        x *= UINT64_C(11400745605648788393);
        x ^= x << 5;
        x += UINT64_C(15485907386656928663) + i;
    }
    return x;
}
static uint64_t f029(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 17;
        x *= UINT64_C(11400746705160416604);
        x ^= x << 6;
        x += UINT64_C(15485907386656887208) + i;
    }
    return x;
}
static uint64_t f030(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 18;
        x *= UINT64_C(11400747804672044815);
        x ^= x << 7;
        x += UINT64_C(15485907386657109985) + i;
    }
    return x;
}
static uint64_t f031(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 19;
        x *= UINT64_C(11400748904183673026);
        x ^= x << 8;
        x += UINT64_C(15485907386657068346) + i;
    }
    return x;
}
static uint64_t f032(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 20;
        x *= UINT64_C(11400750003695301237);
        x ^= x << 9;
        x += UINT64_C(15485907386657028979) + i;
    }
    return x;
}
static uint64_t f033(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 21;
        x *= UINT64_C(11400751103206929448);
        x ^= x << 10;
        x += UINT64_C(15485907386657249412) + i;
    }
    return x;
}
static uint64_t f034(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 5;
        x *= UINT64_C(11400752202718557659);
        x ^= x << 11;
        x += UINT64_C(15485907386657210077) + i;
    }
    return x;
}
static uint64_t f035(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 6;
        x *= UINT64_C(11400753302230185870);
        x ^= x << 12;
        x += UINT64_C(15485907386657168406) + i;
    }
    return x;
}
static uint64_t f036(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 7;
        x *= UINT64_C(11400754401741814081);
        x ^= x << 13;
        x += UINT64_C(15485907386657391151) + i;
    }
    return x;
}
static uint64_t f037(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 8;
        x *= UINT64_C(11400755501253442292);
        x ^= x << 14;
        x += UINT64_C(15485907386657349728) + i;
    }
    return x;
}
static uint64_t f038(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 9;
        x *= UINT64_C(11400756600765070503);
        x ^= x << 15;
        x += UINT64_C(15485907386657309113) + i;
    }
    return x;
}
static uint64_t f039(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 10;
        x *= UINT64_C(11400757700276698714);
        x ^= x << 3;
        x += UINT64_C(15485907386656483314) + i;
    }
    return x;
}
static uint64_t f040(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 11;
        x *= UINT64_C(11400758799788326925);
        x ^= x << 4;
        x += UINT64_C(15485907386656441611) + i;
    }
    return x;
}
static uint64_t f041(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 12;
        x *= UINT64_C(11400759899299955136);
        x ^= x << 5;
        x += UINT64_C(15485907386656402268) + i;
    }
    return x;
}
static uint64_t f042(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 13;
        x *= UINT64_C(11400760998811583347);
        x ^= x << 6;
        x += UINT64_C(15485907386656360597) + i;
    }
    return x;
}
static uint64_t f043(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 14;
        x *= UINT64_C(11400762098323211558);
        x ^= x << 7;
        x += UINT64_C(15485907386656583342) + i;
    }
    return x;
}
static uint64_t f044(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 15;
        x *= UINT64_C(11400763197834839769);
        x ^= x << 8;
        x += UINT64_C(15485907386656541927) + i;
    }
    return x;
}
static uint64_t f045(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 16;
        x *= UINT64_C(11400764297346467980);
        x ^= x << 9;
        x += UINT64_C(15485907386656502328) + i;
    }
    return x;
}
static uint64_t f046(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 17;
        x *= UINT64_C(11400765396858096191);
        x ^= x << 10;
        x += UINT64_C(15485907386656723057) + i;
    }
    return x;
}
static uint64_t f047(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 18;
        x *= UINT64_C(11400766496369724402);
        x ^= x << 11;
        x += UINT64_C(15485907386656682378) + i;
    }
    return x;
}
static uint64_t f048(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 19;
        x *= UINT64_C(11400767595881352613);
        x ^= x << 12;
        x += UINT64_C(15485907386656643011) + i;
    }
    return x;
}
static uint64_t f049(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 20;
        x *= UINT64_C(11400768695392980824);
        x ^= x << 13;
        x += UINT64_C(15485907386656863508) + i;
    }
    return x;
}
static uint64_t f050(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 21;
        x *= UINT64_C(11400769794904609035);
        x ^= x << 14;
        x += UINT64_C(15485907386656824109) + i;
    }
    return x;
}
static uint64_t f051(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 5;
        x *= UINT64_C(11400770894416237246);
        x ^= x << 15;
        x += UINT64_C(15485907386656782694) + i;
    }
    return x;
}
static uint64_t f052(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 6;
        x *= UINT64_C(11400771993927865457);
        x ^= x << 3;
        x += UINT64_C(15485907386660150975) + i;
    }
    return x;
}
static uint64_t f053(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 7;
        x *= UINT64_C(11400773093439493668);
        x ^= x << 4;
        x += UINT64_C(15485907386660109552) + i;
    }
    return x;
}
static uint64_t f054(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 8;
        x *= UINT64_C(11400774192951121879);
        x ^= x << 5;
        x += UINT64_C(15485907386660069897) + i;
    }
    return x;
}
static uint64_t f055(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 9;
        x *= UINT64_C(11400775292462750090);
        x ^= x << 6;
        x += UINT64_C(15485907386660028482) + i;
    }
    return x;
}
static uint64_t f056(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 10;
        x *= UINT64_C(11400776391974378301);
        x ^= x << 7;
        x += UINT64_C(15485907386660250011) + i;
    }
    return x;
}
static uint64_t f057(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 11;
        x *= UINT64_C(11400777491486006512);
        x ^= x << 8;
        x += UINT64_C(15485907386660210604) + i;
    }
    return x;
}
static uint64_t f058(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 12;
        x *= UINT64_C(11400778590997634723);
        x ^= x << 9;
        x += UINT64_C(15485907386660169189) + i;
    }
    return x;
}
static uint64_t f059(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 13;
        x *= UINT64_C(11400779690509262934);
        x ^= x << 10;
        x += UINT64_C(15485907386660391742) + i;
    }
    return x;
}
static uint64_t f060(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 14;
        x *= UINT64_C(11400780790020891145);
        x ^= x << 11;
        x += UINT64_C(15485907386660350327) + i;
    }
    return x;
}
static uint64_t f061(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 15;
        x *= UINT64_C(11400781889532519356);
        x ^= x << 12;
        x += UINT64_C(15485907386660310664) + i;
    }
    return x;
}
static uint64_t f062(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 16;
        x *= UINT64_C(11400782989044147567);
        x ^= x << 13;
        x += UINT64_C(15485907386660531393) + i;
    }
    return x;
}
static uint64_t f063(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 17;
        x *= UINT64_C(11400784088555775778);
        x ^= x << 14;
        x += UINT64_C(15485907386660491802) + i;
    }
    return x;
}
static uint64_t f064(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 18;
        x *= UINT64_C(11400785188067403989);
        x ^= x << 15;
        x += UINT64_C(15485907386660450387) + i;
    }
    return x;
}
static uint64_t f065(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 19;
        x *= UINT64_C(11400786287579032200);
        x ^= x << 3;
        x += UINT64_C(15485907386659624548) + i;
    }
    return x;
}
static uint64_t f066(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 20;
        x *= UINT64_C(11400787387090660411);
        x ^= x << 4;
        x += UINT64_C(15485907386659583933) + i;
    }
    return x;
}
static uint64_t f067(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 21;
        x *= UINT64_C(11400788486602288622);
        x ^= x << 5;
        x += UINT64_C(15485907386659542518) + i;
    }
    return x;
}
static uint64_t f068(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 5;
        x *= UINT64_C(11400789586113916833);
        x ^= x << 6;
        x += UINT64_C(15485907386659765007) + i;
    }
    return x;
}
static uint64_t f069(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 6;
        x *= UINT64_C(11400790685625545044);
        x ^= x << 7;
        x += UINT64_C(15485907386659723584) + i;
    }
    return x;
}
static uint64_t f070(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 7;
        x *= UINT64_C(11400791785137173255);
        x ^= x << 8;
        x += UINT64_C(15485907386659683993) + i;
    }
    return x;
}
static uint64_t f071(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 8;
        x *= UINT64_C(11400792884648801466);
        x ^= x << 9;
        x += UINT64_C(15485907386659642578) + i;
    }
    return x;
}
static uint64_t f072(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 9;
        x *= UINT64_C(11400793984160429677);
        x ^= x << 10;
        x += UINT64_C(15485907386659865323) + i;
    }
    return x;
}
static uint64_t f073(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 10;
        x *= UINT64_C(11400795083672057888);
        x ^= x << 11;
        x += UINT64_C(15485907386659823676) + i;
    }
    return x;
}
static uint64_t f074(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 11;
        x *= UINT64_C(11400796183183686099);
        x ^= x << 12;
        x += UINT64_C(15485907386659784309) + i;
    }
    return x;
}
static uint64_t f075(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 12;
        x *= UINT64_C(11400797282695314310);
        x ^= x << 13;
        x += UINT64_C(15485907386660005774) + i;
    }
    return x;
}
static uint64_t f076(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 13;
        x *= UINT64_C(11400798382206942521);
        x ^= x << 14;
        x += UINT64_C(15485907386659964359) + i;
    }
    return x;
}
static uint64_t f077(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 14;
        x *= UINT64_C(11400799481718570732);
        x ^= x << 15;
        x += UINT64_C(15485907386659924760) + i;
    }
    return x;
}
static uint64_t f078(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 15;
        x *= UINT64_C(11400800581230198943);
        x ^= x << 3;
        x += UINT64_C(15485907386659096913) + i;
    }
    return x;
}
static uint64_t f079(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 16;
        x *= UINT64_C(11400801680741827154);
        x ^= x << 4;
        x += UINT64_C(15485907386659057514) + i;
    }
    return x;
}
static uint64_t f080(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 17;
        x *= UINT64_C(11400802780253455365);
        x ^= x << 5;
        x += UINT64_C(15485907386659015843) + i;
    }
    return x;
}
static uint64_t f081(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 18;
        x *= UINT64_C(11400803879765083576);
        x ^= x << 6;
        x += UINT64_C(15485907386659238644) + i;
    }
    return x;
}
static uint64_t f082(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 19;
        x *= UINT64_C(11400804979276711787);
        x ^= x << 7;
        x += UINT64_C(15485907386659196941) + i;
    }
    return x;
}
static uint64_t f083(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 20;
        x *= UINT64_C(11400806078788339998);
        x ^= x << 8;
        x += UINT64_C(15485907386659157574) + i;
    }
    return x;
}
static uint64_t f084(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 21;
        x *= UINT64_C(11400807178299968209);
        x ^= x << 9;
        x += UINT64_C(15485907386659116959) + i;
    }
    return x;
}
static uint64_t f085(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 5;
        x *= UINT64_C(11400808277811596420);
        x ^= x << 10;
        x += UINT64_C(15485907386659337680) + i;
    }
    return x;
}
static uint64_t f086(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 6;
        x *= UINT64_C(11400809377323224631);
        x ^= x << 11;
        x += UINT64_C(15485907386659298281) + i;
    }
    return x;
}
static uint64_t f087(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 7;
        x *= UINT64_C(11400810476834852842);
        x ^= x << 12;
        x += UINT64_C(15485907386659256610) + i;
    }
    return x;
}
static uint64_t f088(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 8;
        x *= UINT64_C(11400811576346481053);
        x ^= x << 13;
        x += UINT64_C(15485907386659479419) + i;
    }
    return x;
}
static uint64_t f089(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 9;
        x *= UINT64_C(11400812675858109264);
        x ^= x << 14;
        x += UINT64_C(15485907386659437708) + i;
    }
    return x;
}
static uint64_t f090(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 10;
        x *= UINT64_C(11400813775369737475);
        x ^= x << 15;
        x += UINT64_C(15485907386659398341) + i;
    }
    return x;
}
static uint64_t f091(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 11;
        x *= UINT64_C(11400814874881365686);
        x ^= x << 3;
        x += UINT64_C(15485907386658570270) + i;
    }
    return x;
}
static uint64_t f092(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 12;
        x *= UINT64_C(11400815974392993897);
        x ^= x << 4;
        x += UINT64_C(15485907386658530903) + i;
    }
    return x;
}
static uint64_t f093(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 13;
        x *= UINT64_C(11400817073904622108);
        x ^= x << 5;
        x += UINT64_C(15485907386658489448) + i;
    }
    return x;
}
static uint64_t f094(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 14;
        x *= UINT64_C(11400818173416250319);
        x ^= x << 6;
        x += UINT64_C(15485907386658710945) + i;
    }
    return x;
}
static uint64_t f095(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 15;
        x *= UINT64_C(11400819272927878530);
        x ^= x << 7;
        x += UINT64_C(15485907386658671610) + i;
    }
    return x;
}
static uint64_t f096(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 16;
        x *= UINT64_C(11400820372439506741);
        x ^= x << 8;
        x += UINT64_C(15485907386658629939) + i;
    }
    return x;
}
static uint64_t f097(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 17;
        x *= UINT64_C(11400821471951134952);
        x ^= x << 9;
        x += UINT64_C(15485907386658590532) + i;
    }
    return x;
}
static uint64_t f098(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 18;
        x *= UINT64_C(11400822571462763163);
        x ^= x << 10;
        x += UINT64_C(15485907386658811037) + i;
    }
    return x;
}
static uint64_t f099(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 19;
        x *= UINT64_C(11400823670974391374);
        x ^= x << 11;
        x += UINT64_C(15485907386658771670) + i;
    }
    return x;
}
static uint64_t f100(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 20;
        x *= UINT64_C(11400824770486019585);
        x ^= x << 12;
        x += UINT64_C(15485907386658730223) + i;
    }
    return x;
}
static uint64_t f101(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 21;
        x *= UINT64_C(11400825869997647796);
        x ^= x << 13;
        x += UINT64_C(15485907386658952736) + i;
    }
    return x;
}
static uint64_t f102(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 5;
        x *= UINT64_C(11400826969509276007);
        x ^= x << 14;
        x += UINT64_C(15485907386658911353) + i;
    }
    return x;
}
static uint64_t f103(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 6;
        x *= UINT64_C(11400828069020904218);
        x ^= x << 15;
        x += UINT64_C(15485907386658870706) + i;
    }
    return x;
}
static uint64_t f104(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 7;
        x *= UINT64_C(11400829168532532429);
        x ^= x << 3;
        x += UINT64_C(15485907386653850571) + i;
    }
    return x;
}
static uint64_t f105(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 8;
        x *= UINT64_C(11400830268044160640);
        x ^= x << 4;
        x += UINT64_C(15485907386653808924) + i;
    }
    return x;
}
static uint64_t f106(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 9;
        x *= UINT64_C(11400831367555788851);
        x ^= x << 5;
        x += UINT64_C(15485907386653769557) + i;
    }
    return x;
}
static uint64_t f107(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 10;
        x *= UINT64_C(11400832467067417062);
        x ^= x << 6;
        x += UINT64_C(15485907386653990254) + i;
    }
    return x;
}
static uint64_t f108(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 11;
        x *= UINT64_C(11400833566579045273);
        x ^= x << 7;
        x += UINT64_C(15485907386653950631) + i;
    }
    return x;
}
static uint64_t f109(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 12;
        x *= UINT64_C(11400834666090673484);
        x ^= x << 8;
        x += UINT64_C(15485907386653909240) + i;
    }
    return x;
}
static uint64_t f110(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 13;
        x *= UINT64_C(11400835765602301695);
        x ^= x << 9;
        x += UINT64_C(15485907386653869617) + i;
    }
    return x;
}
static uint64_t f111(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 14;
        x *= UINT64_C(11400836865113929906);
        x ^= x << 10;
        x += UINT64_C(15485907386654090314) + i;
    }
    return x;
}
static uint64_t f112(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 15;
        x *= UINT64_C(11400837964625558117);
        x ^= x << 11;
        x += UINT64_C(15485907386654049667) + i;
    }
    return x;
}
static uint64_t f113(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 16;
        x *= UINT64_C(11400839064137186328);
        x ^= x << 12;
        x += UINT64_C(15485907386654010324) + i;
    }
    return x;
}
static uint64_t f114(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 17;
        x *= UINT64_C(11400840163648814539);
        x ^= x << 13;
        x += UINT64_C(15485907386654231021) + i;
    }
    return x;
}
static uint64_t f115(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 18;
        x *= UINT64_C(11400841263160442750);
        x ^= x << 14;
        x += UINT64_C(15485907386654191398) + i;
    }
    return x;
}
static uint64_t f116(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 19;
        x *= UINT64_C(11400842362672070961);
        x ^= x << 15;
        x += UINT64_C(15485907386654150015) + i;
    }
    return x;
}
static uint64_t f117(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 20;
        x *= UINT64_C(11400843462183699172);
        x ^= x << 3;
        x += UINT64_C(15485907386653323952) + i;
    }
    return x;
}
static uint64_t f118(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 21;
        x *= UINT64_C(11400844561695327383);
        x ^= x << 4;
        x += UINT64_C(15485907386653282505) + i;
    }
    return x;
}
static uint64_t f119(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 5;
        x *= UINT64_C(11400845661206955594);
        x ^= x << 5;
        x += UINT64_C(15485907386653242882) + i;
    }
    return x;
}
static uint64_t f120(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 6;
        x *= UINT64_C(11400846760718583805);
        x ^= x << 6;
        x += UINT64_C(15485907386653463643) + i;
    }
    return x;
}
static uint64_t f121(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 7;
        x *= UINT64_C(11400847860230212016);
        x ^= x << 7;
        x += UINT64_C(15485907386653424236) + i;
    }
    return x;
}
static uint64_t f122(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 8;
        x *= UINT64_C(11400848959741840227);
        x ^= x << 8;
        x += UINT64_C(15485907386653383589) + i;
    }
    return x;
}
static uint64_t f123(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 9;
        x *= UINT64_C(11400850059253468438);
        x ^= x << 9;
        x += UINT64_C(15485907386653604350) + i;
    }
    return x;
}
static uint64_t f124(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 10;
        x *= UINT64_C(11400851158765096649);
        x ^= x << 10;
        x += UINT64_C(15485907386653564727) + i;
    }
    return x;
}
static uint64_t f125(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 11;
        x *= UINT64_C(11400852258276724860);
        x ^= x << 11;
        x += UINT64_C(15485907386653523272) + i;
    }
    return x;
}
static uint64_t f126(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 12;
        x *= UINT64_C(11400853357788353071);
        x ^= x << 12;
        x += UINT64_C(15485907386653483649) + i;
    }
    return x;
}
static uint64_t f127(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 13;
        x *= UINT64_C(11400854457299981282);
        x ^= x << 13;
        x += UINT64_C(15485907386653704410) + i;
    }
    return x;
}
static uint64_t f128(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 14;
        x *= UINT64_C(11400855556811609493);
        x ^= x << 14;
        x += UINT64_C(15485907386653664787) + i;
    }
    return x;
}
static uint64_t f129(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 15;
        x *= UINT64_C(11400856656323237704);
        x ^= x << 15;
        x += UINT64_C(15485907386653623332) + i;
    }
    return x;
}
static uint64_t f130(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 16;
        x *= UINT64_C(11400857755834865915);
        x ^= x << 3;
        x += UINT64_C(15485907386652797565) + i;
    }
    return x;
}
static uint64_t f131(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 17;
        x *= UINT64_C(11400858855346494126);
        x ^= x << 4;
        x += UINT64_C(15485907386652756918) + i;
    }
    return x;
}
static uint64_t f132(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 18;
        x *= UINT64_C(11400859954858122337);
        x ^= x << 5;
        x += UINT64_C(15485907386652715471) + i;
    }
    return x;
}
static uint64_t f133(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 19;
        x *= UINT64_C(11400861054369750548);
        x ^= x << 6;
        x += UINT64_C(15485907386652937984) + i;
    }
    return x;
}
static uint64_t f134(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 20;
        x *= UINT64_C(11400862153881378759);
        x ^= x << 7;
        x += UINT64_C(15485907386652896601) + i;
    }
    return x;
}
static uint64_t f135(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 21;
        x *= UINT64_C(11400863253393006970);
        x ^= x << 8;
        x += UINT64_C(15485907386652856978) + i;
    }
    return x;
}
static uint64_t f136(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 5;
        x *= UINT64_C(11400864352904635181);
        x ^= x << 9;
        x += UINT64_C(15485907386653077675) + i;
    }
    return x;
}
static uint64_t f137(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 6;
        x *= UINT64_C(11400865452416263392);
        x ^= x << 10;
        x += UINT64_C(15485907386653038332) + i;
    }
    return x;
}
static uint64_t f138(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 7;
        x *= UINT64_C(11400866551927891603);
        x ^= x << 11;
        x += UINT64_C(15485907386652996661) + i;
    }
    return x;
}
static uint64_t f139(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 8;
        x *= UINT64_C(11400867651439519814);
        x ^= x << 12;
        x += UINT64_C(15485907386652957262) + i;
    }
    return x;
}
static uint64_t f140(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 9;
        x *= UINT64_C(11400868750951148025);
        x ^= x << 13;
        x += UINT64_C(15485907386653178759) + i;
    }
    return x;
}
static uint64_t f141(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 10;
        x *= UINT64_C(11400869850462776236);
        x ^= x << 14;
        x += UINT64_C(15485907386653137368) + i;
    }
    return x;
}
static uint64_t f142(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 11;
        x *= UINT64_C(11400870949974404447);
        x ^= x << 15;
        x += UINT64_C(15485907386653097745) + i;
    }
    return x;
}
static uint64_t f143(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 12;
        x *= UINT64_C(11400872049486032658);
        x ^= x << 3;
        x += UINT64_C(15485907386652269866) + i;
    }
    return x;
}
static uint64_t f144(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 13;
        x *= UINT64_C(11400873148997660869);
        x ^= x << 4;
        x += UINT64_C(15485907386652230499) + i;
    }
    return x;
}
static uint64_t f145(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 14;
        x *= UINT64_C(11400874248509289080);
        x ^= x << 5;
        x += UINT64_C(15485907386652188852) + i;
    }
    return x;
}
static uint64_t f146(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 15;
        x *= UINT64_C(11400875348020917291);
        x ^= x << 6;
        x += UINT64_C(15485907386652411597) + i;
    }
    return x;
}
static uint64_t f147(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 16;
        x *= UINT64_C(11400876447532545502);
        x ^= x << 7;
        x += UINT64_C(15485907386652369926) + i;
    }
    return x;
}
static uint64_t f148(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 17;
        x *= UINT64_C(11400877547044173713);
        x ^= x << 8;
        x += UINT64_C(15485907386652330591) + i;
    }
    return x;
}
static uint64_t f149(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 18;
        x *= UINT64_C(11400878646555801924);
        x ^= x << 9;
        x += UINT64_C(15485907386652552080) + i;
    }
    return x;
}
static uint64_t f150(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 19;
        x *= UINT64_C(11400879746067430135);
        x ^= x << 10;
        x += UINT64_C(15485907386652510633) + i;
    }
    return x;
}
static uint64_t f151(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 20;
        x *= UINT64_C(11400880845579058346);
        x ^= x << 11;
        x += UINT64_C(15485907386652471266) + i;
    }
    return x;
}
static uint64_t f152(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 21;
        x *= UINT64_C(11400881945090686557);
        x ^= x << 12;
        x += UINT64_C(15485907386652429627) + i;
    }
    return x;
}
static uint64_t f153(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 5;
        x *= UINT64_C(11400883044602314768);
        x ^= x << 13;
        x += UINT64_C(15485907386652652364) + i;
    }
    return x;
}
static uint64_t f154(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 6;
        x *= UINT64_C(11400884144113942979);
        x ^= x << 14;
        x += UINT64_C(15485907386652610693) + i;
    }
    return x;
}
static uint64_t f155(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 7;
        x *= UINT64_C(11400885243625571190);
        x ^= x << 15;
        x += UINT64_C(15485907386652571358) + i;
    }
    return x;
}
static uint64_t f156(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 8;
        x *= UINT64_C(11400886343137199401);
        x ^= x << 3;
        x += UINT64_C(15485907386655937559) + i;
    }
    return x;
}
static uint64_t f157(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 9;
        x *= UINT64_C(11400887442648827612);
        x ^= x << 4;
        x += UINT64_C(15485907386655898152) + i;
    }
    return x;
}
static uint64_t f158(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 10;
        x *= UINT64_C(11400888542160455823);
        x ^= x << 5;
        x += UINT64_C(15485907386655856737) + i;
    }
    return x;
}
static uint64_t f159(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 11;
        x *= UINT64_C(11400889641672084034);
        x ^= x << 6;
        x += UINT64_C(15485907386656078266) + i;
    }
    return x;
}
static uint64_t f160(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 12;
        x *= UINT64_C(11400890741183712245);
        x ^= x << 7;
        x += UINT64_C(15485907386656038899) + i;
    }
    return x;
}
static uint64_t f161(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 13;
        x *= UINT64_C(11400891840695340456);
        x ^= x << 8;
        x += UINT64_C(15485907386655997188) + i;
    }
    return x;
}
static uint64_t f162(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 14;
        x *= UINT64_C(11400892940206968667);
        x ^= x << 9;
        x += UINT64_C(15485907386656219997) + i;
    }
    return x;
}
static uint64_t f163(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 15;
        x *= UINT64_C(11400894039718596878);
        x ^= x << 10;
        x += UINT64_C(15485907386656178326) + i;
    }
    return x;
}
static uint64_t f164(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 16;
        x *= UINT64_C(11400895139230225089);
        x ^= x << 11;
        x += UINT64_C(15485907386656138927) + i;
    }
    return x;
}
static uint64_t f165(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 17;
        x *= UINT64_C(11400896238741853300);
        x ^= x << 12;
        x += UINT64_C(15485907386656097504) + i;
    }
    return x;
}
static uint64_t f166(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 18;
        x *= UINT64_C(11400897338253481511);
        x ^= x << 13;
        x += UINT64_C(15485907386656320057) + i;
    }
    return x;
}
static uint64_t f167(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 19;
        x *= UINT64_C(11400898437765109722);
        x ^= x << 14;
        x += UINT64_C(15485907386656278642) + i;
    }
    return x;
}
static uint64_t f168(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 20;
        x *= UINT64_C(11400899537276737933);
        x ^= x << 15;
        x += UINT64_C(15485907386656237963) + i;
    }
    return x;
}
static uint64_t f169(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 21;
        x *= UINT64_C(11400900636788366144);
        x ^= x << 3;
        x += UINT64_C(15485907386655412188) + i;
    }
    return x;
}
static uint64_t f170(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 5;
        x *= UINT64_C(11400901736299994355);
        x ^= x << 4;
        x += UINT64_C(15485907386655370517) + i;
    }
    return x;
}
static uint64_t f171(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 6;
        x *= UINT64_C(11400902835811622566);
        x ^= x << 5;
        x += UINT64_C(15485907386655331118) + i;
    }
    return x;
}
static uint64_t f172(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 7;
        x *= UINT64_C(11400903935323250777);
        x ^= x << 6;
        x += UINT64_C(15485907386655551847) + i;
    }
    return x;
}
static uint64_t f173(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 8;
        x *= UINT64_C(11400905034834878988);
        x ^= x << 7;
        x += UINT64_C(15485907386655512248) + i;
    }
    return x;
}
static uint64_t f174(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 9;
        x *= UINT64_C(11400906134346507199);
        x ^= x << 8;
        x += UINT64_C(15485907386655470833) + i;
    }
    return x;
}
static uint64_t f175(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 10;
        x *= UINT64_C(11400907233858135410);
        x ^= x << 9;
        x += UINT64_C(15485907386655693322) + i;
    }
    return x;
}
static uint64_t f176(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 11;
        x *= UINT64_C(11400908333369763621);
        x ^= x << 10;
        x += UINT64_C(15485907386655651907) + i;
    }
    return x;
}
static uint64_t f177(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 12;
        x *= UINT64_C(11400909432881391832);
        x ^= x << 11;
        x += UINT64_C(15485907386655611284) + i;
    }
    return x;
}
static uint64_t f178(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 13;
        x *= UINT64_C(11400910532393020043);
        x ^= x << 12;
        x += UINT64_C(15485907386655834029) + i;
    }
    return x;
}
static uint64_t f179(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 14;
        x *= UINT64_C(11400911631904648254);
        x ^= x << 13;
        x += UINT64_C(15485907386655792614) + i;
    }
    return x;
}
static uint64_t f180(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 15;
        x *= UINT64_C(11400912731416276465);
        x ^= x << 14;
        x += UINT64_C(15485907386655753023) + i;
    }
    return x;
}
static uint64_t f181(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 16;
        x *= UINT64_C(11400913830927904676);
        x ^= x << 15;
        x += UINT64_C(15485907386655711600) + i;
    }
    return x;
}
static uint64_t f182(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 17;
        x *= UINT64_C(11400914930439532887);
        x ^= x << 3;
        x += UINT64_C(15485907386654885513) + i;
    }
    return x;
}
static uint64_t f183(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 18;
        x *= UINT64_C(11400916029951161098);
        x ^= x << 4;
        x += UINT64_C(15485907386654844098) + i;
    }
    return x;
}
static uint64_t f184(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 19;
        x *= UINT64_C(11400917129462789309);
        x ^= x << 5;
        x += UINT64_C(15485907386654804507) + i;
    }
    return x;
}
static uint64_t f185(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 20;
        x *= UINT64_C(11400918228974417520);
        x ^= x << 6;
        x += UINT64_C(15485907386655025196) + i;
    }
    return x;
}
static uint64_t f186(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 21;
        x *= UINT64_C(11400919328486045731);
        x ^= x << 7;
        x += UINT64_C(15485907386654985829) + i;
    }
    return x;
}
static uint64_t f187(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 5;
        x *= UINT64_C(11400920427997673942);
        x ^= x << 8;
        x += UINT64_C(15485907386654945214) + i;
    }
    return x;
}
static uint64_t f188(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 6;
        x *= UINT64_C(11400921527509302153);
        x ^= x << 9;
        x += UINT64_C(15485907386655165943) + i;
    }
    return x;
}
static uint64_t f189(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 7;
        x *= UINT64_C(11400922627020930364);
        x ^= x << 10;
        x += UINT64_C(15485907386655126280) + i;
    }
    return x;
}
static uint64_t f190(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 8;
        x *= UINT64_C(11400923726532558575);
        x ^= x << 11;
        x += UINT64_C(15485907386655084865) + i;
    }
    return x;
}
static uint64_t f191(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 9;
        x *= UINT64_C(11400924826044186786);
        x ^= x << 12;
        x += UINT64_C(15485907386655307418) + i;
    }
    return x;
}
static uint64_t f192(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 10;
        x *= UINT64_C(11400925925555814997);
        x ^= x << 13;
        x += UINT64_C(15485907386655266003) + i;
    }
    return x;
}
static uint64_t f193(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 11;
        x *= UINT64_C(11400927025067443208);
        x ^= x << 14;
        x += UINT64_C(15485907386655226596) + i;
    }
    return x;
}
static uint64_t f194(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 12;
        x *= UINT64_C(11400928124579071419);
        x ^= x << 15;
        x += UINT64_C(15485907386655184957) + i;
    }
    return x;
}
static uint64_t f195(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 13;
        x *= UINT64_C(11400929224090699630);
        x ^= x << 3;
        x += UINT64_C(15485907386654359158) + i;
    }
    return x;
}
static uint64_t f196(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 14;
        x *= UINT64_C(11400930323602327841);
        x ^= x << 4;
        x += UINT64_C(15485907386654318479) + i;
    }
    return x;
}
static uint64_t f197(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 15;
        x *= UINT64_C(11400931423113956052);
        x ^= x << 5;
        x += UINT64_C(15485907386654277056) + i;
    }
    return x;
}
static uint64_t f198(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 16;
        x *= UINT64_C(11400932522625584263);
        x ^= x << 6;
        x += UINT64_C(15485907386654499609) + i;
    }
    return x;
}
static uint64_t f199(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 17;
        x *= UINT64_C(11400933622137212474);
        x ^= x << 7;
        x += UINT64_C(15485907386654458194) + i;
    }
    return x;
}
static uint64_t f200(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 18;
        x *= UINT64_C(11400934721648840685);
        x ^= x << 8;
        x += UINT64_C(15485907386654418795) + i;
    }
    return x;
}
static uint64_t f201(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 19;
        x *= UINT64_C(11400935821160468896);
        x ^= x << 9;
        x += UINT64_C(15485907386654639292) + i;
    }
    return x;
}
static uint64_t f202(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 20;
        x *= UINT64_C(11400936920672097107);
        x ^= x << 10;
        x += UINT64_C(15485907386654599925) + i;
    }
    return x;
}
static uint64_t f203(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 21;
        x *= UINT64_C(11400938020183725318);
        x ^= x << 11;
        x += UINT64_C(15485907386654558222) + i;
    }
    return x;
}
static uint64_t f204(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 5;
        x *= UINT64_C(11400939119695353529);
        x ^= x << 12;
        x += UINT64_C(15485907386654780999) + i;
    }
    return x;
}
static uint64_t f205(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 6;
        x *= UINT64_C(11400940219206981740);
        x ^= x << 13;
        x += UINT64_C(15485907386654740376) + i;
    }
    return x;
}
static uint64_t f206(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 7;
        x *= UINT64_C(11400941318718609951);
        x ^= x << 14;
        x += UINT64_C(15485907386654698961) + i;
    }
    return x;
}
static uint64_t f207(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 8;
        x *= UINT64_C(11400942418230238162);
        x ^= x << 15;
        x += UINT64_C(15485907386654659562) + i;
    }
    return x;
}
static uint64_t f208(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 9;
        x *= UINT64_C(11400943517741866373);
        x ^= x << 3;
        x += UINT64_C(15485907386666414371) + i;
    }
    return x;
}
static uint64_t f209(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 10;
        x *= UINT64_C(11400944617253494584);
        x ^= x << 4;
        x += UINT64_C(15485907386666375028) + i;
    }
    return x;
}
static uint64_t f210(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 11;
        x *= UINT64_C(11400945716765122795);
        x ^= x << 5;
        x += UINT64_C(15485907386666333325) + i;
    }
    return x;
}
static uint64_t f211(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 12;
        x *= UINT64_C(11400946816276751006);
        x ^= x << 6;
        x += UINT64_C(15485907386666556102) + i;
    }
    return x;
}
static uint64_t f212(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 13;
        x *= UINT64_C(11400947915788379217);
        x ^= x << 7;
        x += UINT64_C(15485907386666514463) + i;
    }
    return x;
}
static uint64_t f213(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 14;
        x *= UINT64_C(11400949015300007428);
        x ^= x << 8;
        x += UINT64_C(15485907386666475088) + i;
    }
    return x;
}
static uint64_t f214(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 15;
        x *= UINT64_C(11400950114811635639);
        x ^= x << 9;
        x += UINT64_C(15485907386666695785) + i;
    }
    return x;
}
static uint64_t f215(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 16;
        x *= UINT64_C(11400951214323263850);
        x ^= x << 10;
        x += UINT64_C(15485907386666655138) + i;
    }
    return x;
}
static uint64_t f216(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 17;
        x *= UINT64_C(11400952313834892061);
        x ^= x << 11;
        x += UINT64_C(15485907386666615803) + i;
    }
    return x;
}
static uint64_t f217(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 18;
        x *= UINT64_C(11400953413346520272);
        x ^= x << 12;
        x += UINT64_C(15485907386666836236) + i;
    }
    return x;
}
static uint64_t f218(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 19;
        x *= UINT64_C(11400954512858148483);
        x ^= x << 13;
        x += UINT64_C(15485907386666796869) + i;
    }
    return x;
}
static uint64_t f219(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 20;
        x *= UINT64_C(11400955612369776694);
        x ^= x << 14;
        x += UINT64_C(15485907386666755230) + i;
    }
    return x;
}
static uint64_t f220(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 21;
        x *= UINT64_C(11400956711881404905);
        x ^= x << 15;
        x += UINT64_C(15485907386666715863) + i;
    }
    return x;
}
static uint64_t f221(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 5;
        x *= UINT64_C(11400957811393033116);
        x ^= x << 3;
        x += UINT64_C(15485907386665887976) + i;
    }
    return x;
}
static uint64_t f222(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 6;
        x *= UINT64_C(11400958910904661327);
        x ^= x << 4;
        x += UINT64_C(15485907386665848353) + i;
    }
    return x;
}
static uint64_t f223(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 7;
        x *= UINT64_C(11400960010416289538);
        x ^= x << 5;
        x += UINT64_C(15485907386665806970) + i;
    }
    return x;
}
static uint64_t f224(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 8;
        x *= UINT64_C(11400961109927917749);
        x ^= x << 6;
        x += UINT64_C(15485907386666028467) + i;
    }
    return x;
}
static uint64_t f225(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 9;
        x *= UINT64_C(11400962209439545960);
        x ^= x << 7;
        x += UINT64_C(15485907386665989060) + i;
    }
    return x;
}
static uint64_t f226(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 10;
        x *= UINT64_C(11400963308951174171);
        x ^= x << 8;
        x += UINT64_C(15485907386665947421) + i;
    }
    return x;
}
static uint64_t f227(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 11;
        x *= UINT64_C(11400964408462802382);
        x ^= x << 9;
        x += UINT64_C(15485907386666170198) + i;
    }
    return x;
}
static uint64_t f228(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 12;
        x *= UINT64_C(11400965507974430593);
        x ^= x << 10;
        x += UINT64_C(15485907386666128751) + i;
    }
    return x;
}
static uint64_t f229(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 13;
        x *= UINT64_C(11400966607486058804);
        x ^= x << 11;
        x += UINT64_C(15485907386666089120) + i;
    }
    return x;
}
static uint64_t f230(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 14;
        x *= UINT64_C(11400967706997687015);
        x ^= x << 12;
        x += UINT64_C(15485907386666309881) + i;
    }
    return x;
}
static uint64_t f231(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 15;
        x *= UINT64_C(11400968806509315226);
        x ^= x << 13;
        x += UINT64_C(15485907386666270258) + i;
    }
    return x;
}
static uint64_t f232(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 16;
        x *= UINT64_C(11400969906020943437);
        x ^= x << 14;
        x += UINT64_C(15485907386666228811) + i;
    }
    return x;
}
static uint64_t f233(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 17;
        x *= UINT64_C(11400971005532571648);
        x ^= x << 15;
        x += UINT64_C(15485907386665401756) + i;
    }
    return x;
}
static uint64_t f234(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 18;
        x *= UINT64_C(11400972105044199859);
        x ^= x << 3;
        x += UINT64_C(15485907386665362389) + i;
    }
    return x;
}
static uint64_t f235(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 19;
        x *= UINT64_C(11400973204555828070);
        x ^= x << 4;
        x += UINT64_C(15485907386665320942) + i;
    }
    return x;
}
static uint64_t f236(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 20;
        x *= UINT64_C(11400974304067456281);
        x ^= x << 5;
        x += UINT64_C(15485907386665281319) + i;
    }
    return x;
}
static uint64_t f237(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 21;
        x *= UINT64_C(11400975403579084492);
        x ^= x << 6;
        x += UINT64_C(15485907386665502072) + i;
    }
    return x;
}
static uint64_t f238(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 5;
        x *= UINT64_C(11400976503090712703);
        x ^= x << 7;
        x += UINT64_C(15485907386665462449) + i;
    }
    return x;
}
static uint64_t f239(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 6;
        x *= UINT64_C(11400977602602340914);
        x ^= x << 8;
        x += UINT64_C(15485907386665421002) + i;
    }
    return x;
}
static uint64_t f240(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 7;
        x *= UINT64_C(11400978702113969125);
        x ^= x << 9;
        x += UINT64_C(15485907386665643523) + i;
    }
    return x;
}
static uint64_t f241(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 8;
        x *= UINT64_C(11400979801625597336);
        x ^= x << 10;
        x += UINT64_C(15485907386665602132) + i;
    }
    return x;
}
static uint64_t f242(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 9;
        x *= UINT64_C(11400980901137225547);
        x ^= x << 11;
        x += UINT64_C(15485907386665562733) + i;
    }
    return x;
}
static uint64_t f243(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 10;
        x *= UINT64_C(11400982000648853758);
        x ^= x << 12;
        x += UINT64_C(15485907386665784230) + i;
    }
    return x;
}
static uint64_t f244(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 11;
        x *= UINT64_C(11400983100160481969);
        x ^= x << 13;
        x += UINT64_C(15485907386665742847) + i;
    }
    return x;
}
static uint64_t f245(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 12;
        x *= UINT64_C(11400984199672110180);
        x ^= x << 14;
        x += UINT64_C(15485907386665703216) + i;
    }
    return x;
}
static uint64_t f246(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 13;
        x *= UINT64_C(11400985299183738391);
        x ^= x << 15;
        x += UINT64_C(15485907386664875337) + i;
    }
    return x;
}
static uint64_t f247(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 14;
        x *= UINT64_C(11400986398695366602);
        x ^= x << 3;
        x += UINT64_C(15485907386664835714) + i;
    }
    return x;
}
static uint64_t f248(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 15;
        x *= UINT64_C(11400987498206994813);
        x ^= x << 4;
        x += UINT64_C(15485907386664794331) + i;
    }
    return x;
}
static uint64_t f249(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 16;
        x *= UINT64_C(11400988597718623024);
        x ^= x << 5;
        x += UINT64_C(15485907386664754924) + i;
    }
    return x;
}
static uint64_t f250(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 17;
        x *= UINT64_C(11400989697230251235);
        x ^= x << 6;
        x += UINT64_C(15485907386664975397) + i;
    }
    return x;
}
static uint64_t f251(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 18;
        x *= UINT64_C(11400990796741879446);
        x ^= x << 7;
        x += UINT64_C(15485907386664936062) + i;
    }
    return x;
}
static uint64_t f252(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 19;
        x *= UINT64_C(11400991896253507657);
        x ^= x << 8;
        x += UINT64_C(15485907386664895415) + i;
    }
    return x;
}
static uint64_t f253(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 20;
        x *= UINT64_C(11400992995765135868);
        x ^= x << 9;
        x += UINT64_C(15485907386665116104) + i;
    }
    return x;
}
static uint64_t f254(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 21;
        x *= UINT64_C(11400994095276764079);
        x ^= x << 10;
        x += UINT64_C(15485907386665076481) + i;
    }
    return x;
}
static uint64_t f255(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 5;
        x *= UINT64_C(11400995194788392290);
        x ^= x << 11;
        x += UINT64_C(15485907386665035098) + i;
    }
    return x;
}
static uint64_t f256(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 6;
        x *= UINT64_C(11400996294300020501);
        x ^= x << 12;
        x += UINT64_C(15485907386665257619) + i;
    }
    return x;
}
static uint64_t f257(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 7;
        x *= UINT64_C(11400997393811648712);
        x ^= x << 13;
        x += UINT64_C(15485907386665216164) + i;
    }
    return x;
}
static uint64_t f258(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 8;
        x *= UINT64_C(11400998493323276923);
        x ^= x << 14;
        x += UINT64_C(15485907386665176829) + i;
    }
    return x;
}
static uint64_t f259(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 9;
        x *= UINT64_C(11400999592834905134);
        x ^= x << 15;
        x += UINT64_C(15485907386668543030) + i;
    }
    return x;
}
static uint64_t f260(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 10;
        x *= UINT64_C(11401000692346533345);
        x ^= x << 3;
        x += UINT64_C(15485907386668503631) + i;
    }
    return x;
}
static uint64_t f261(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 11;
        x *= UINT64_C(11401001791858161556);
        x ^= x << 4;
        x += UINT64_C(15485907386668462976) + i;
    }
    return x;
}
static uint64_t f262(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 12;
        x *= UINT64_C(11401002891369789767);
        x ^= x << 5;
        x += UINT64_C(15485907386668421593) + i;
    }
    return x;
}
static uint64_t f263(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 13;
        x *= UINT64_C(11401003990881417978);
        x ^= x << 6;
        x += UINT64_C(15485907386668644114) + i;
    }
    return x;
}
static uint64_t f264(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 14;
        x *= UINT64_C(11401005090393046189);
        x ^= x << 7;
        x += UINT64_C(15485907386668602667) + i;
    }
    return x;
}
static uint64_t f265(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 15;
        x *= UINT64_C(11401006189904674400);
        x ^= x << 8;
        x += UINT64_C(15485907386668563324) + i;
    }
    return x;
}
static uint64_t f266(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 16;
        x *= UINT64_C(11401007289416302611);
        x ^= x << 9;
        x += UINT64_C(15485907386668783797) + i;
    }
    return x;
}
static uint64_t f267(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 17;
        x *= UINT64_C(11401008388927930822);
        x ^= x << 10;
        x += UINT64_C(15485907386668744398) + i;
    }
    return x;
}
static uint64_t f268(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 18;
        x *= UINT64_C(11401009488439559033);
        x ^= x << 11;
        x += UINT64_C(15485907386668702727) + i;
    }
    return x;
}
static uint64_t f269(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 19;
        x *= UINT64_C(11401010587951187244);
        x ^= x << 12;
        x += UINT64_C(15485907386668925528) + i;
    }
    return x;
}
static uint64_t f270(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 20;
        x *= UINT64_C(11401011687462815455);
        x ^= x << 13;
        x += UINT64_C(15485907386668884881) + i;
    }
    return x;
}
static uint64_t f271(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 21;
        x *= UINT64_C(11401012786974443666);
        x ^= x << 14;
        x += UINT64_C(15485907386668843434) + i;
    }
    return x;
}
static uint64_t f272(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 5;
        x *= UINT64_C(11401013886486071877);
        x ^= x << 15;
        x += UINT64_C(15485907386668017635) + i;
    }
    return x;
}
static uint64_t f273(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 6;
        x *= UINT64_C(11401014985997700088);
        x ^= x << 3;
        x += UINT64_C(15485907386667975988) + i;
    }
    return x;
}
static uint64_t f274(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 7;
        x *= UINT64_C(11401016085509328299);
        x ^= x << 4;
        x += UINT64_C(15485907386667936589) + i;
    }
    return x;
}
static uint64_t f275(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 8;
        x *= UINT64_C(11401017185020956510);
        x ^= x << 5;
        x += UINT64_C(15485907386667894918) + i;
    }
    return x;
}
static uint64_t f276(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 9;
        x *= UINT64_C(11401018284532584721);
        x ^= x << 6;
        x += UINT64_C(15485907386668117727) + i;
    }
    return x;
}
static uint64_t f277(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 10;
        x *= UINT64_C(11401019384044212932);
        x ^= x << 7;
        x += UINT64_C(15485907386668076048) + i;
    }
    return x;
}
static uint64_t f278(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 11;
        x *= UINT64_C(11401020483555841143);
        x ^= x << 8;
        x += UINT64_C(15485907386668036649) + i;
    }
    return x;
}
static uint64_t f279(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 12;
        x *= UINT64_C(11401021583067469354);
        x ^= x << 9;
        x += UINT64_C(15485907386668257378) + i;
    }
    return x;
}
static uint64_t f280(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 13;
        x *= UINT64_C(11401022682579097565);
        x ^= x << 10;
        x += UINT64_C(15485907386668216763) + i;
    }
    return x;
}
static uint64_t f281(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 14;
        x *= UINT64_C(11401023782090725776);
        x ^= x << 11;
        x += UINT64_C(15485907386668177356) + i;
    }
    return x;
}
static uint64_t f282(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 15;
        x *= UINT64_C(11401024881602353987);
        x ^= x << 12;
        x += UINT64_C(15485907386668397829) + i;
    }
    return x;
}
static uint64_t f283(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 16;
        x *= UINT64_C(11401025981113982198);
        x ^= x << 13;
        x += UINT64_C(15485907386668358494) + i;
    }
    return x;
}
static uint64_t f284(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 17;
        x *= UINT64_C(11401027080625610409);
        x ^= x << 14;
        x += UINT64_C(15485907386668316823) + i;
    }
    return x;
}
static uint64_t f285(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 18;
        x *= UINT64_C(11401028180137238620);
        x ^= x << 15;
        x += UINT64_C(15485907386667490984) + i;
    }
    return x;
}
static uint64_t f286(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 19;
        x *= UINT64_C(11401029279648866831);
        x ^= x << 3;
        x += UINT64_C(15485907386667449569) + i;
    }
    return x;
}
static uint64_t f287(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 20;
        x *= UINT64_C(11401030379160495042);
        x ^= x << 4;
        x += UINT64_C(15485907386667409978) + i;
    }
    return x;
}
static uint64_t f288(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 21;
        x *= UINT64_C(11401031478672123253);
        x ^= x << 5;
        x += UINT64_C(15485907386667368563) + i;
    }
    return x;
}
static uint64_t f289(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 5;
        x *= UINT64_C(11401032578183751464);
        x ^= x << 6;
        x += UINT64_C(15485907386667590020) + i;
    }
    return x;
}
static uint64_t f290(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 6;
        x *= UINT64_C(11401033677695379675);
        x ^= x << 7;
        x += UINT64_C(15485907386667550685) + i;
    }
    return x;
}
static uint64_t f291(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 7;
        x *= UINT64_C(11401034777207007886);
        x ^= x << 8;
        x += UINT64_C(15485907386667509014) + i;
    }
    return x;
}
static uint64_t f292(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 8;
        x *= UINT64_C(11401035876718636097);
        x ^= x << 9;
        x += UINT64_C(15485907386667731759) + i;
    }
    return x;
}
static uint64_t f293(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 9;
        x *= UINT64_C(11401036976230264308);
        x ^= x << 10;
        x += UINT64_C(15485907386667690336) + i;
    }
    return x;
}
static uint64_t f294(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 10;
        x *= UINT64_C(11401038075741892519);
        x ^= x << 11;
        x += UINT64_C(15485907386667650745) + i;
    }
    return x;
}
static uint64_t f295(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 11;
        x *= UINT64_C(11401039175253520730);
        x ^= x << 12;
        x += UINT64_C(15485907386667871474) + i;
    }
    return x;
}
static uint64_t f296(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 12;
        x *= UINT64_C(11401040274765148941);
        x ^= x << 13;
        x += UINT64_C(15485907386667831819) + i;
    }
    return x;
}
static uint64_t f297(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 13;
        x *= UINT64_C(11401041374276777152);
        x ^= x << 14;
        x += UINT64_C(15485907386667790428) + i;
    }
    return x;
}
static uint64_t f298(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 14;
        x *= UINT64_C(11401042473788405363);
        x ^= x << 15;
        x += UINT64_C(15485907386666963349) + i;
    }
    return x;
}
static uint64_t f299(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 15;
        x *= UINT64_C(11401043573300033574);
        x ^= x << 3;
        x += UINT64_C(15485907386666923950) + i;
    }
    return x;
}
static uint64_t f300(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 16;
        x *= UINT64_C(11401044672811661785);
        x ^= x << 4;
        x += UINT64_C(15485907386666882535) + i;
    }
    return x;
}
static uint64_t f301(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 17;
        x *= UINT64_C(11401045772323289996);
        x ^= x << 5;
        x += UINT64_C(15485907386667105080) + i;
    }
    return x;
}
static uint64_t f302(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 18;
        x *= UINT64_C(11401046871834918207);
        x ^= x << 6;
        x += UINT64_C(15485907386667063665) + i;
    }
    return x;
}
static uint64_t f303(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 19;
        x *= UINT64_C(11401047971346546418);
        x ^= x << 7;
        x += UINT64_C(15485907386667024010) + i;
    }
    return x;
}
static uint64_t f304(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 20;
        x *= UINT64_C(11401049070858174629);
        x ^= x << 8;
        x += UINT64_C(15485907386666982595) + i;
    }
    return x;
}
static uint64_t f305(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 21;
        x *= UINT64_C(11401050170369802840);
        x ^= x << 9;
        x += UINT64_C(15485907386667205140) + i;
    }
    return x;
}
static uint64_t f306(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 5;
        x *= UINT64_C(11401051269881431051);
        x ^= x << 10;
        x += UINT64_C(15485907386667163693) + i;
    }
    return x;
}
static uint64_t f307(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 6;
        x *= UINT64_C(11401052369393059262);
        x ^= x << 11;
        x += UINT64_C(15485907386667124326) + i;
    }
    return x;
}
static uint64_t f308(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 7;
        x *= UINT64_C(11401053468904687473);
        x ^= x << 12;
        x += UINT64_C(15485907386667345855) + i;
    }
    return x;
}
static uint64_t f309(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 8;
        x *= UINT64_C(11401054568416315684);
        x ^= x << 13;
        x += UINT64_C(15485907386667304432) + i;
    }
    return x;
}
static uint64_t f310(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 9;
        x *= UINT64_C(11401055667927943895);
        x ^= x << 14;
        x += UINT64_C(15485907386667264777) + i;
    }
    return x;
}
static uint64_t f311(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 10;
        x *= UINT64_C(11401056767439572106);
        x ^= x << 15;
        x += UINT64_C(15485907386662242626) + i;
    }
    return x;
}
static uint64_t f312(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 11;
        x *= UINT64_C(11401057866951200317);
        x ^= x << 3;
        x += UINT64_C(15485907386662203035) + i;
    }
    return x;
}
static uint64_t f313(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 12;
        x *= UINT64_C(11401058966462828528);
        x ^= x << 4;
        x += UINT64_C(15485907386662161580) + i;
    }
    return x;
}
static uint64_t f314(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 13;
        x *= UINT64_C(11401060065974456739);
        x ^= x << 5;
        x += UINT64_C(15485907386662384357) + i;
    }
    return x;
}
static uint64_t f315(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 14;
        x *= UINT64_C(11401061165486084950);
        x ^= x << 6;
        x += UINT64_C(15485907386662342718) + i;
    }
    return x;
}
static uint64_t f316(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 15;
        x *= UINT64_C(11401062264997713161);
        x ^= x << 7;
        x += UINT64_C(15485907386662303351) + i;
    }
    return x;
}
static uint64_t f317(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 16;
        x *= UINT64_C(11401063364509341372);
        x ^= x << 8;
        x += UINT64_C(15485907386662262664) + i;
    }
    return x;
}
static uint64_t f318(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 17;
        x *= UINT64_C(11401064464020969583);
        x ^= x << 9;
        x += UINT64_C(15485907386662483393) + i;
    }
    return x;
}
static uint64_t f319(uint64_t x) {
    for (unsigned i = 0; i < 48; ++i) {
        x ^= x >> 18;
        x *= UINT64_C(11401065563532597794);
        x ^= x << 10;
        x += UINT64_C(15485907386662443802) + i;
    }
    return x;
}

static fn_t funcs[] = {
    f000, f001, f002, f003, f004, f005, f006, f007,
    f008, f009, f010, f011, f012, f013, f014, f015,
    f016, f017, f018, f019, f020, f021, f022, f023,
    f024, f025, f026, f027, f028, f029, f030, f031,
    f032, f033, f034, f035, f036, f037, f038, f039,
    f040, f041, f042, f043, f044, f045, f046, f047,
    f048, f049, f050, f051, f052, f053, f054, f055,
    f056, f057, f058, f059, f060, f061, f062, f063,
    f064, f065, f066, f067, f068, f069, f070, f071,
    f072, f073, f074, f075, f076, f077, f078, f079,
    f080, f081, f082, f083, f084, f085, f086, f087,
    f088, f089, f090, f091, f092, f093, f094, f095,
    f096, f097, f098, f099, f100, f101, f102, f103,
    f104, f105, f106, f107, f108, f109, f110, f111,
    f112, f113, f114, f115, f116, f117, f118, f119,
    f120, f121, f122, f123, f124, f125, f126, f127,
    f128, f129, f130, f131, f132, f133, f134, f135,
    f136, f137, f138, f139, f140, f141, f142, f143,
    f144, f145, f146, f147, f148, f149, f150, f151,
    f152, f153, f154, f155, f156, f157, f158, f159,
    f160, f161, f162, f163, f164, f165, f166, f167,
    f168, f169, f170, f171, f172, f173, f174, f175,
    f176, f177, f178, f179, f180, f181, f182, f183,
    f184, f185, f186, f187, f188, f189, f190, f191,
    f192, f193, f194, f195, f196, f197, f198, f199,
    f200, f201, f202, f203, f204, f205, f206, f207,
    f208, f209, f210, f211, f212, f213, f214, f215,
    f216, f217, f218, f219, f220, f221, f222, f223,
    f224, f225, f226, f227, f228, f229, f230, f231,
    f232, f233, f234, f235, f236, f237, f238, f239,
    f240, f241, f242, f243, f244, f245, f246, f247,
    f248, f249, f250, f251, f252, f253, f254, f255,
    f256, f257, f258, f259, f260, f261, f262, f263,
    f264, f265, f266, f267, f268, f269, f270, f271,
    f272, f273, f274, f275, f276, f277, f278, f279,
    f280, f281, f282, f283, f284, f285, f286, f287,
    f288, f289, f290, f291, f292, f293, f294, f295,
    f296, f297, f298, f299, f300, f301, f302, f303,
    f304, f305, f306, f307, f308, f309, f310, f311,
    f312, f313, f314, f315, f316, f317, f318, f319,
};

int main(void) {
    uint64_t x = UINT64_C(0x123456789abcdef0);
    for (unsigned round = 0; round < 64; ++round) {
        for (unsigned i = 0; i < sizeof(funcs)/sizeof(funcs[0]); ++i) x = funcs[i](x + round);
    }
    printf("%llu\n", (unsigned long long)x);
    return 0;
}
