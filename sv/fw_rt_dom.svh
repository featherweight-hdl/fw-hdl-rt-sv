// fw_rt_dom.svh: the rt-sv domain runtime (fw-hdl-spec semantics/domains.md).
// Included inside fw_hdl_pkg, after fw_rt.svh.
//
// A domain object's record is an __fw_rt_obj of kind __FW_K_DOMAIN; the
// associations, drivers and stated port names and derivations live in the
// records of the objects that hold them. The kind-generic bodies of
// fw_domain #(K) (fw_rt_domain.svh) pass the kind's handle and the %p text
// of its params here.
//
// Domain handles inside a params value cannot be told apart in %p (Verilator
// prints a nested handle as its class name), so the params JSON writes the
// handles it can reach by name: every kind's `from`, and fw_reset_kind's
// `clock`. A handle in another field of a user kind is written as its class
// name.

// A kind's params value, or a pin attribute value, held with its type.
virtual class __fw_rt_held_base;
endclass

class __fw_rt_held #(type T = int) extends __fw_rt_held_base;
    T v;
endclass

// A waiver made by waive().
class __fw_rt_waiver;
    __fw_rt_obj         scope;
    fw_domain_kind_type k;
    __fw_rt_obj         a, b;
    string              reason;
    bit                 matched;
endclass

class __fw_rt_dom;
    static fw_domain_kind_type kinds[string];   // kinds with an association
    static __fw_rt_waiver      waivers[$];
    static bit                 crossed[string]; // pairs reported or waived
    static fw_severity_e       sev_opt[string]; // +fw_dom_sev, by "kind.relation"
    static bit                 sev_read;

    static function string key(fw_domain_kind_type k, string name);
        return {k.name(), "/", name};
    endfunction

    // The kind name and association name of a table key.
    static function void split_key(string ky, output string kname, output string name);
        int i = 0;
        while (i < ky.len() && ky[i] != "/") i++;
        kname = ky.substr(0, i - 1);
        name = (i + 1 < ky.len()) ? ky.substr(i + 1, ky.len() - 1) : "";
    endfunction

    static function string jpath(__fw_rt_obj o);
        return o == null ? "null" : __fw_rt_str::jstr(o.path);
    endfunction

    // The JSON of a struct value printed with %p: its fields, with `from`
    // and (when has_clock) `clock` written as paths.
    static function string val_json(string pstr, __fw_rt_obj from[$], bit has_clock,
                                    __fw_rt_obj clock, ref __fw_rt_field fs[$]);
        __fw_rt_pj pj = new;
        string r = "{";
        pj.fields(pstr, fs);
        foreach (fs[i]) begin
            if (fs[i].name == "from") begin
                string l = "[";
                foreach (from[j]) l = {l, j ? ", " : "", jpath(from[j])};
                fs[i].json = {l, "]"};
            end else if (fs[i].name == "clock" && has_clock) fs[i].json = jpath(clock);
            r = {r, i ? ", " : "", __fw_rt_str::jstr(fs[i].name), ": ", fs[i].json};
        end
        return {r, "}"};
    endfunction

    static function string attr_json(string pstr);
        __fw_rt_obj none[$];
        __fw_rt_field fs[$];
        return val_json(pstr, none, 0, null, fs);
    endfunction

    static function bit is_reset(fw_domain_kind_type k);
        return k == fw_reset_kind::get_type();
    endfunction

    // A reset params value's clock.
    static function fw_domain_base reset_clock(__fw_rt_held_base h);
        __fw_rt_held #(fw_reset_kind::params_t) r;
        if ($cast(r, h)) return r.v.clock;
        return null;
    endfunction

    static function string field(__fw_rt_field fs[$], string name);
        foreach (fs[i]) if (fs[i].name == name) return fs[i].json;
        return "";
    endfunction

    // ---- creation ----

    // Creates the record of domain d. Sources (and a reset's clock) are
    // checked first: an error stops the call, and d gets a detached record.
    static function void create(fw_domain_base d, string name, fw_component parent,
                                fw_domain_kind_type k, string raw_type,
                                __fw_rt_held_base held, fw_domain_base from[$], string pstr);
        __fw_rt_obj p = __fw_rt::impl(parent);
        __fw_rt_obj o, srcs[$], clk;
        fw_domain_base ch;
        string path = (p == null) ? name : {p.path, ".", name};
        bit bad = 0;
        foreach (from[i]) begin
            __fw_rt_obj s = __fw_rt::impl(from[i]);
            if (from[i] == null) begin
                __fw_rt::diag("FW-E-DOM-NONE", path, "a derivation source is null");
                bad = 1;
            end else if (s == null || s.kind != __FW_K_DOMAIN || s.dkind != k) begin
                __fw_rt::diag("FW-E-DOM-KIND", path, {"a source is not a domain of kind ", k.name()});
                bad = 1;
            end else srcs.push_back(s);
        end
        if (is_reset(k)) begin
            ch = reset_clock(held);
            clk = __fw_rt::impl(ch);
            if (ch != null && (clk == null || clk.kind != __FW_K_DOMAIN
                               || clk.dkind != fw_clock_kind::get_type())) begin
                __fw_rt::diag("FW-E-DOM-KIND", path, "the reset's clock is not a clock domain");
                bad = 1;
            end
        end
        if (bad) begin
            o = new;
            o.name = name;
            o.path = path;
            o.kind = __FW_K_DOMAIN;
            o.parent = p;
            o.detached = 1;
        end else o = __fw_rt::new_obj(name, parent, __FW_K_DOMAIN, raw_type, __FW_D_NONE, 0);
        o.dkind = k;
        o.dheld = held;
        o.dfrom = srcs;
        o.dclock = clk;
        o.dparams_json = val_json(pstr, srcs, is_reset(k), clk, o.dfields);
        __fw_rt::attach(d, o);
    endfunction

    // ---- association and lookup ----

    static function void set(fw_object h, fw_domain_base dh, string name, fw_domain_kind_type k);
        __fw_rt_obj o = __fw_rt::impl(h), d = __fw_rt::impl(dh), c = __fw_rt::cur;
        string ky = key(k, name);
        if (o == null || o.detached) return;
        if (__fw_rt::phase != __FW_P_BUILD || c == null) begin
            __fw_rt::diag("FW-E-DOM-PHASE", o.path, "set outside the build phase");
            return;
        end
        if (!(o == c || (o.parent == c && (o.kind == __FW_K_COMPONENT || o.kind == __FW_K_PORT
                                           || o.kind == __FW_K_API || o.is_bundle())))) begin
            __fw_rt::diag("FW-E-DOM-OBJ", o.path, {"not the calling component (", c.path,
                          "), a direct child, or one of its interfaces"});
            return;
        end
        if (name != "" && o.kind != __FW_K_COMPONENT) begin
            __fw_rt::diag("FW-E-DOM-OBJ", o.path, "a named association on an interface");
            return;
        end
        if (d == null || d.detached) return;
        if (o.assoc.exists(ky)) begin
            __fw_rt::diag("FW-E-DOM-BIND", o.path, {"already associated (", ky, ")"});
            return;
        end
        o.assoc[ky] = d;
        kinds[k.name()] = k;
    endfunction

    // The domain o resolves to for kind kname (domains.md, Lookup). mark:
    // a read of a named association.
    static function __fw_rt_obj get(__fw_rt_obj o, string kname, string name, bit mark);
        string dk = {kname, "/"};
        __fw_rt_obj c;
        if (o == null) return null;
        if (o.kind == __FW_K_COMPONENT) begin
            string nk = {kname, "/", name};
            if (name != "" && o.assoc.exists(nk)) begin
                if (mark) o.aread[nk] = 1;
                return o.assoc[nk];
            end
            for (c = o; c != null; c = c.parent)
                if (c.assoc.exists(dk)) return c.assoc[dk];
            return null;
        end
        for (c = o; c != null && c.kind != __FW_K_COMPONENT; c = c.parent)
            if (c.assoc.exists(dk)) return c.assoc[dk];
        return get(o.scope(), kname, "", 0);
    endfunction

    static function __fw_rt_obj get_h(fw_object h, string name, fw_domain_kind_type k);
        __fw_rt_obj o = __fw_rt::impl(h);
        if (o == null) return null;
        if (name != "" && o.kind != __FW_K_COMPONENT) begin
            __fw_rt::diag("FW-E-DOM-OBJ", o.path, "a named association on an interface");
            return null;
        end
        return get(o, k.name(), name, 1);
    endfunction

    // ---- relation ----

    static function void roots(__fw_rt_obj d, ref bit r[string]);
        if (d.dfrom.size() == 0) r[d.path] = 1;
        foreach (d.dfrom[i]) roots(d.dfrom[i], r);
    endfunction

    static function fw_domain_rel_e relate(__fw_rt_obj a, __fw_rt_obj b);
        bit ra[string], rb[string];
        if (a == b) return FW_DOMAIN_SAME;
        roots(a, ra);
        roots(b, rb);
        foreach (ra[k]) if (rb.exists(k)) return FW_DOMAIN_RELATED;
        return FW_DOMAIN_UNRELATED;
    endfunction

    static function fw_domain_rel_e relate_h(fw_domain_base a, fw_domain_base b);
        __fw_rt_obj ra = __fw_rt::impl(a), rb = __fw_rt::impl(b);
        if (ra == null || rb == null) begin
            __fw_rt::diag("FW-E-DOM-NONE", __fw_rt::cur_path(), "relate of a null domain");
            return FW_DOMAIN_UNRELATED;
        end
        return relate(ra, rb);
    endfunction

    // ---- drivers and pins ----

    static function void add_driver(__fw_rt_obj d, string ky, string js);
        d.drv_keys.push_back(ky);
        d.drv_json.push_back(js);
        d.realized = 1;
    endfunction

    static function void drive(fw_domain_base dh, fw_domain_kind_type k, fw_signal_base sh, string apstr);
        __fw_rt_obj d = __fw_rt::impl(dh), s = __fw_rt::impl(sh), c = __fw_rt::cur;
        if (d == null || d.detached) return;
        if (__fw_rt::phase != __FW_P_CONNECT || c == null) begin
            __fw_rt::diag("FW-E-DOM-PHASE", d.path, "drive outside the connect phase");
            return;
        end
        if (s == null || s.detached) return;
        if (!k.physical()) begin
            __fw_rt::diag("FW-E-DOM-PIN", s.path, {"drives a domain of marker kind ", k.name()});
            return;
        end
        if (s.width > 1) begin
            __fw_rt::diag("FW-E-DOM-PIN", s.path, "a domain driver wider than 1 bit");
            return;
        end
        if (!(s.scope() == c || (s.kind == __FW_K_PORT && s.scope() != null
                                 && s.scope().parent == c))) begin
            __fw_rt::diag("FW-E-CONN-SCOPE", s.path, {"not in the scope of ", c.path});
            return;
        end
        begin
            __fw_rt_obj none[$];
            __fw_rt_field fs[$];
            string aj = val_json(apstr, none, 0, null, fs);
            add_driver(d, s.path, {"{\"signal\": ", __fw_rt_str::jstr(s.path),
                                   ", \"attr\": ", aj, "}"});
            d.dsig = s;
            d.dlow = field(fs, "active_low") == "1";
        end
    endfunction

    // pin() (out = 0) and pin_out() (out = 1) of the extern map being filled.
    static function void pin(string name, fw_domain_kind_type k, fw_domain_base dh, bit out,
                             string apstr);
        __fw_rt_obj x, d;
        __fw_rt_dpin p;
        __fw_rt_field af[$];
        __fw_rt_obj none[$];
        if (__fw_rt::xm == null || __fw_rt::xm.comp == null) return;
        x = __fw_rt::xm.comp;
        if (!k.physical()) begin
            __fw_rt::diag("FW-E-DOM-PIN", x.path, {"pin '", name, "' of marker kind ", k.name()});
            return;
        end
        d = (dh == null && !out) ? get(x, k.name(), "", 1) : __fw_rt::impl(dh);
        if (d != null && d.detached) return;
        if (d == null)
            __fw_rt::diag("FW-E-DOM-NONE", x.path, {"pin '", name, "' has no domain"});
        p = new;
        p.pin = name;
        p.kname = k.name();
        p.dom = d;
        p.out = out;
        p.attr = val_json(apstr, none, 0, null, af);
        __fw_rt::xm.dpins.push_back(p);
        if (d == null) return;
        d.realized = 1;
        if (out)
            add_driver(d, {x.path, " ", name}, {"{\"extern\": ", __fw_rt_str::jstr(x.path),
                       ", \"pin\": ", __fw_rt_str::jstr(name), ", \"attr\": ", p.attr, "}"});
        else if (is_reset(k)) begin
            string want = field(af, "style");
            if (want != $sformatf("%0d", fw_reset_kind::ANY) && want != field(d.dfields, "style"))
                __fw_rt::diag("FW-W-DOM-STYLE", x.path, {"pin '", name, "' expects another reset style"});
        end
    endfunction

    // The "domain_pins" member of an extern record, or "" when there are none.
    static function string dpins_json(__fw_rt_dpin ps[$]);
        string by_pin[string];
        string r = ", \"domain_pins\": {";
        int n = 0;
        if (ps.size() == 0) return "";
        foreach (ps[i])
            if (!by_pin.exists(ps[i].pin))
                by_pin[ps[i].pin] = {"{\"kind\": ", __fw_rt_str::jstr(ps[i].kname),
                                     ", \"domain\": ", jpath(ps[i].dom),
                                     ", \"dir\": \"", ps[i].out ? "out" : "in",
                                     "\", \"attr\": ", ps[i].attr, "}"};
        foreach (by_pin[k]) r = {r, n++ ? ", " : "", __fw_rt_str::jstr(k), ": ", by_pin[k]};
        return {r, "}"};
    endfunction

    // ---- statements a component makes about its class ----

    static function bit own(fw_component comp, string what, output __fw_rt_obj o);
        o = __fw_rt::impl(comp);
        if (o == null || o.detached) return 0;
        if (__fw_rt::phase != __FW_P_BUILD) begin
            __fw_rt::diag("FW-E-DOM-PHASE", o.path, {what, " outside the build phase"});
            return 0;
        end
        if (o != __fw_rt::cur) begin
            __fw_rt::diag("FW-E-DOM-OBJ", o.path, {what, " on a component other than the caller"});
            return 0;
        end
        return 1;
    endfunction

    static function void port_name(fw_component comp, fw_domain_kind_type k, string assoc, string port);
        __fw_rt_obj o;
        if (own(comp, "port_name", o)) o.pnames[key(k, assoc)] = port;
    endfunction

    static function void provides(fw_component comp, fw_domain_kind_type k, string assoc,
                                  __fw_rt_held_base held, fw_domain_base from[$], string pstr);
        __fw_rt_obj o, srcs[$];
        __fw_rt_field fs[$];
        if (!own(comp, "provides", o)) return;
        foreach (from[i]) srcs.push_back(__fw_rt::impl(from[i]));
        o.provs[key(k, assoc)] = val_json(pstr, srcs, is_reset(k),
                                          is_reset(k) ? __fw_rt::impl(reset_clock(held)) : null, fs);
    endfunction

    static function void waive(fw_domain_kind_type k, fw_object ha, fw_object hb, string reason);
        __fw_rt_obj a = __fw_rt::impl(ha), b = __fw_rt::impl(hb);
        __fw_rt_waiver w;
        if (a == null || b == null || a.detached || b.detached) return;
        if (__fw_rt::phase != __FW_P_CONNECT || __fw_rt::cur == null) begin
            __fw_rt::diag("FW-E-DOM-PHASE", a.path, "waive outside the connect phase");
            return;
        end
        if (reason == "") begin
            __fw_rt::diag("FW-E-DOM-WAIVE", a.path, "a waiver needs a reason");
            return;
        end
        w = new;
        w.scope = __fw_rt::cur;
        w.k = k;
        w.a = a;
        w.b = b;
        w.reason = reason;
        waivers.push_back(w);
    endfunction

    // ---- crossings ----

    // +fw_dom_sev=kind.relation=severity[,...]: crossing severities that
    // override the kinds' own. A relation is same, related or unrelated; a
    // severity none, info, warning or error.
    static function void read_sev();
        string opt, item;
        sev_read = 1;
        if (!$value$plusargs("fw_dom_sev=%s", opt)) return;
        opt = {opt, ","};
        for (int i = 0; i < opt.len(); i++) begin
            if (opt[i] != ",") begin
                item = {item, opt.substr(i, i)};
                continue;
            end
            if (item != "") sev_item(item);
            item = "";
        end
    endfunction

    static function void sev_item(string item);
        int dot = -1, eq = -1;
        string kr, rel, sv;
        fw_severity_e sev;
        for (int i = 0; i < item.len(); i++)
            if (item[i] == "=" && eq < 0) eq = i;
        for (int i = 0; i < eq; i++)
            if (item[i] == ".") dot = i;
        if (dot <= 0 || eq < 0) begin
            __fw_rt::diag("FW-E-RT-OPT", "", {"+fw_dom_sev: '", item,
                                              "': expected kind.relation=severity"});
            return;
        end
        kr = item.substr(0, eq - 1);
        rel = item.substr(dot + 1, eq - 1);
        sv = eq + 1 < item.len() ? item.substr(eq + 1, item.len() - 1) : "";
        if (rel != "same" && rel != "related" && rel != "unrelated") begin
            __fw_rt::diag("FW-E-RT-OPT", "", {"+fw_dom_sev: '", item,
                                              "': the relation is same, related or unrelated"});
            return;
        end
        case (sv)
            "none":    sev = FW_SEV_NONE;
            "info":    sev = FW_SEV_INFO;
            "warning": sev = FW_SEV_WARNING;
            "error":   sev = FW_SEV_ERROR;
            default: begin
                __fw_rt::diag("FW-E-RT-OPT", "", {"+fw_dom_sev: '", item,
                                                  "': the severity is none, info, warning or error"});
                return;
            end
        endcase
        sev_opt[kr] = sev;
    endfunction

    // The severity of a crossing of kind kn between domains related by rel.
    static function fw_severity_e severity(string kn, fw_domain_rel_e rel);
        string r = rel == FW_DOMAIN_SAME ? "same" : rel == FW_DOMAIN_RELATED ? "related" : "unrelated";
        if (!sev_read) read_sev();
        if (sev_opt.exists({kn, ".", r})) return sev_opt[{kn, ".", r}];
        return kinds[kn].severity(rel);
    endfunction

    // An endpoint's interface: its outermost enclosing bundle, else itself.
    static function __fw_rt_obj iface(__fw_rt_obj e);
        __fw_rt_obj r = e;
        for (__fw_rt_obj c = e.parent; c != null && c.kind != __FW_K_COMPONENT; c = c.parent)
            if (c.is_bundle()) r = c;
        return r;
    endfunction

    // The crossing check of one net of scope s: srcs are its source
    // endpoints, eps all its interface endpoints.
    static function void check_net(__fw_rt_obj s, __fw_rt_obj srcs[$], __fw_rt_obj eps[$]);
        foreach (srcs[i]) foreach (eps[j]) begin
            __fw_rt_obj ia = iface(srcs[i]), ib = iface(eps[j]);
            if (ia == ib) continue;
            foreach (kinds[kn]) begin
                __fw_rt_obj da = get(srcs[i], kn, "", 0), db = get(eps[j], kn, "", 0);
                __fw_rt_obj lo = ia.path < ib.path ? ia : ib, hi = ia.path < ib.path ? ib : ia;
                string pk = {kn, "/", lo.path, " ", hi.path};
                fw_domain_rel_e rel;
                fw_severity_e sev;
                bit waived = 0;
                if (da == null || db == null || da == db || crossed.exists(pk)) continue;
                rel = relate(da, db);
                sev = severity(kn, rel);
                if (sev == FW_SEV_NONE) continue;
                crossed[pk] = 1;
                foreach (waivers[w])
                    if (waivers[w].scope == s && waivers[w].k == kinds[kn]
                        && ((waivers[w].a == lo && waivers[w].b == hi)
                            || (waivers[w].a == hi && waivers[w].b == lo))) begin
                        waivers[w].matched = 1;
                        waived = 1;
                    end
                if (waived) continue;
                __fw_rt::diag(sev == FW_SEV_ERROR ? "FW-E-DOM-CROSS"
                              : sev == FW_SEV_WARNING ? "FW-W-DOM-CROSS" : "FW-I-DOM-CROSS",
                              lo.path, {kn, " crossing from ", da.path, " to ", db.path,
                                        " (", hi.path, ")"});
            end
        end
    endfunction

    // ---- end of elaboration ----

    static function void check();
        fw_domain_kind_type ck = fw_clock_kind::get_type(), rk = fw_reset_kind::get_type();
        if (!sev_read) read_sev();         // a bad option is reported with no crossing too
        foreach (waivers[i])
            if (!waivers[i].matched)
                __fw_rt::diag("FW-W-DOM-WAIVE", waivers[i].a.path, "the waiver matches no crossing");
        foreach (__fw_rt::objs[i]) begin
            __fw_rt_obj o = __fw_rt::objs[i];
            if (o.kind == __FW_K_DOMAIN) begin
                if (o.drv_keys.size() > 1)
                    __fw_rt::diag("FW-E-DOM-DRIVER", o.path, "more than one driver");
                else if (o.realized && o.drv_keys.size() == 0)
                    __fw_rt::diag("FW-E-DOM-NODRIVER", o.path, "realized, but nothing drives it");
            end
            if (o.kind != __FW_K_COMPONENT) continue;
            foreach (o.assoc[ky]) begin
                string kn, nm;
                split_key(ky, kn, nm);
                if (nm != "" && !o.aread.exists(ky))
                    __fw_rt::diag("FW-E-DOM-UNUSED", o.path, {"named association '", nm, "' is never read"});
            end
            foreach (o.provs[ky]) begin
                string kn, nm;
                __fw_rt_obj d;
                split_key(ky, kn, nm);
                d = get(o, kn, nm, 0);
                if (d != null && d.dparams_json != o.provs[ky])
                    __fw_rt::diag("FW-E-DOM-DERIV", o.path, {"'", nm, "' resolves to ", d.path,
                                  ", whose derivation is not the one stated"});
            end
            begin
                __fw_rt_obj rd = get(o, rk.name(), "", 0), cd = get(o, ck.name(), "", 0);
                if (rd != null && cd != null && rd.dclock != null
                    && relate(rd.dclock, cd) == FW_DOMAIN_UNRELATED
                    && (o.parent == null || get(o.parent, rk.name(), "", 0) != rd
                        || get(o.parent, ck.name(), "", 0) != cd))
                    __fw_rt::diag("FW-W-DOM-RSTSYNC", o.path, {"reset ", rd.path, " is synchronous to ",
                                  rd.dclock.path, ", unrelated to clock ", cd.path});
            end
        end
    endfunction

    // ---- netlist ----

    static function string map2_json(string m[string]);
        string r = "{", cur_k = "";
        int n = 0;
        foreach (m[ky]) begin
            string kn, nm;
            split_key(ky, kn, nm);
            if (kn != cur_k) begin
                if (n) r = {r, "}, "};
                r = {r, __fw_rt_str::jstr(kn), ": {"};
                cur_k = kn;
                n = 0;
            end
            r = {r, n++ ? ", " : "", __fw_rt_str::jstr(nm), ": ", m[ky]};
        end
        return {r, "}}"};
    endfunction

    // The domain members of o's netlist record, each with a leading ", ".
    static function string json(__fw_rt_obj o);
        string r = "";
        if (o.kind == __FW_K_DOMAIN) begin
            string ks[$], byk[string];
            r = {r, ", \"drivers\": ["};
            foreach (o.drv_keys[i]) begin
                string k = o.drv_keys[i];
                while (byk.exists(k)) k = {k, " "};
                byk[k] = o.drv_json[i];
            end
            foreach (byk[k]) ks.push_back(k);
            foreach (ks[i]) r = {r, i ? ", " : "", byk[ks[i]]};
            return {r, "]"};
        end
        if (o.assoc.size()) begin
            string m[string];
            foreach (o.assoc[ky]) m[ky] = __fw_rt_str::jstr(o.assoc[ky].path);
            r = {r, ", \"assoc\": ", map2_json(m)};
        end
        if (o.kind != __FW_K_COMPONENT) return r;
        begin
            string ws[string], ks[$];
            foreach (waivers[i])
                if (waivers[i].scope == o)
                    ws[{waivers[i].a.path, " ", waivers[i].b.path, " ", waivers[i].k.name(), " ",
                        $sformatf("%0d", i)}] =
                        {"{\"kind\": ", __fw_rt_str::jstr(waivers[i].k.name()),
                         ", \"a\": ", __fw_rt_str::jstr(waivers[i].a.path),
                         ", \"b\": ", __fw_rt_str::jstr(waivers[i].b.path),
                         ", \"reason\": ", __fw_rt_str::jstr(waivers[i].reason), "}"};
            if (ws.size()) begin
                foreach (ws[k]) ks.push_back(k);
                r = {r, ", \"waivers\": ["};
                foreach (ks[i]) r = {r, i ? ", " : "", ws[ks[i]]};
                r = {r, "]"};
            end
        end
        if (o.pnames.size()) begin
            string m[string];
            foreach (o.pnames[ky]) m[ky] = __fw_rt_str::jstr(o.pnames[ky]);
            r = {r, ", \"port_names\": ", map2_json(m)};
        end
        if (o.provs.size()) r = {r, ", \"provides\": ", map2_json(o.provs)};
        return r;
    endfunction

endclass
