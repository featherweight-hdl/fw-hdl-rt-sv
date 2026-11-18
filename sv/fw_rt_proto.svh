// fw_rt_proto.svh: the rt-sv protocol registry. Included inside
// fw_hdl_pkg, after fw_rt.svh. Semantics: fw-hdl-spec semantics/protocols.md.
//
// Registration runs from the macros (fw_hdl_macros.svh): a protocol's
// record is made by its first get_type() call, which runs declare(); a
// converter registers from a static initializer of its class, so a
// parameterized one registers only for the specializations in the image;
// a bundle instance registers from a member initializer, and its type is
// added to the protocol's bundles when fw_bundle/fw_mirror/fw_monitor
// creates it.

// A family: the protocol class without parameters.
class __fw_rt_family extends fw_protocol_family;
    string n;
    string pfx;
endclass

// A converter registration: a transactor (from == to, with a role) or an
// abstractor (from is the lower protocol).
class __fw_rt_conv;
    string                  ty;         // canonical type spelling
    fw_protocol_type        from, to;
    fw_proto_role_e         role;
    bit                     is_xtor;
    fw_ctor #(fw_component) ctor;
endclass

// A specialization's record.
class __fw_rt_proto_rec;
    fw_protocol_type h;
    string           n;                 // canonical name
    __fw_rt_family   fam;
    fw_api_type      req, rsp;
    string           bundles[$];
    __fw_rt_conv     convs[$];          // converters with this protocol on a side
endclass

class __fw_rt_proto;
    static __fw_rt_family    fams[string];          // by family name
    static __fw_rt_proto_rec recs[fw_protocol_type];
    static __fw_rt_proto_rec order[$];              // in registration order
    static string            api_names[fw_api_type];
    static fw_protocol_type  inst_proto[fw_object]; // bundle and socket instances
    static __fw_rt_conv      conv_by_type[string];  // component type -> converter
    static __fw_rt_proto_rec cur;                   // the record declare() fills

    // The text inside the outermost #( ) of a type name; "" if none.
    static function string params_of(string n);
        for (int i = 0; i + 1 < n.len(); i++)
            if (n[i] == "#" && n[i + 1] == "(") return n.substr(i + 2, n.len() - 2);
        return "";
    endfunction

    // A type name without its parameters.
    static function string family_of(string n);
        for (int i = 0; i + 1 < n.len(); i++)
            if (n[i] == "#" && n[i + 1] == "(") return n.substr(0, i - 1);
        return n;
    endfunction

    static function __fw_rt_proto_rec rec(fw_protocol_type h);
        if (h == null || !recs.exists(h)) return null;
        return recs[h];
    endfunction

    // ---- registration ----

    // Makes the record of specialization h (canonical name raw) in family
    // fname, then runs the protocol's declare() through the caller: the
    // caller brackets P::declare(d) with begin_decl/end_decl.
    static function __fw_rt_proto_rec begin_decl(fw_protocol_type h, string fname, string raw);
        __fw_rt_proto_rec r = new;
        __fw_rt_proto_rec prev = cur;
        r.h = h;
        r.n = __fw_rt_str::tn(raw);
        if (!fams.exists(fname)) begin
            __fw_rt_family f = new;
            f.n = fname;
            f.pfx = (fname.len() > 6 && fname.substr(fname.len() - 6, fname.len() - 1) == "_proto")
                    ? fname.substr(0, fname.len() - 7) : fname;
            fams[fname] = f;
        end
        r.fam = fams[fname];
        recs[h] = r;
        order.push_back(r);
        cur = r;
        return prev;
    endfunction

    static function void end_decl(__fw_rt_proto_rec prev);
        cur = prev;
    endfunction

    static function void decl_api(fw_api_type a, fw_proto_dir_e dir);
        if (cur == null || a == null) return;
        if (a == cur.req || a == cur.rsp) begin
            __fw_rt::diag("FW-E-PROTO-API", cur.n, {"API ", a.name(), " is registered twice"});
            return;
        end
        if (dir == FW_PROTO_REQ) begin
            if (cur.req != null) begin
                __fw_rt::diag("FW-E-PROTO-API", cur.n, "two APIs for direction req");
                return;
            end
            cur.req = a;
        end else begin
            if (cur.rsp != null) begin
                __fw_rt::diag("FW-E-PROTO-API", cur.n, "two APIs for direction rsp");
                return;
            end
            cur.rsp = a;
        end
    endfunction

    static function void decl_prefix(string s);
        if (cur != null) cur.fam.pfx = s;
    endfunction

    static function void add_api(fw_api_type a, string raw);
        api_names[a] = __fw_rt_str::tn(raw);
    endfunction

    // A converter class's registration (static initializer).
    static function bit add_conv(string raw, fw_protocol_type from, fw_protocol_type to,
                                 fw_proto_role_e role, bit is_xtor,
                                 fw_ctor #(fw_component) ctor);
        __fw_rt_conv c = new;
        __fw_rt_proto_rec rf = rec(from), rt = rec(to);
        c.ty = __fw_rt_str::tn(raw);
        c.from = from;
        c.to = to;
        c.role = role;
        c.is_xtor = is_xtor;
        c.ctor = ctor;
        conv_by_type[c.ty] = c;
        if (rf != null) rf.convs.push_back(c);
        if (rt != null && rt != rf) rt.convs.push_back(c);
        return 1;
    endfunction

    // A bundle instance's registration (member initializer).
    static function bit bundle_inst(fw_object b, fw_protocol_type p);
        inst_proto[b] = p;
        return 1;
    endfunction

    // Called by the bundle-role create bodies: adds the bundle type to its
    // protocol's bundles.
    static function void bundle_created(fw_object b, string raw);
        __fw_rt_proto_rec r;
        string n;
        if (!inst_proto.exists(b)) return;
        r = rec(inst_proto[b]);
        if (r == null) return;
        if (__fw_rt::impl(b) != null) __fw_rt::impl(b).aproto = r.n;
        n = __fw_rt_str::tn(raw);
        foreach (r.bundles[i]) if (r.bundles[i] == n) return;
        r.bundles.push_back(n);
    endfunction

    // ---- queries ----

    static function fw_protocol_type of(fw_object x);
        __fw_rt_obj o;
        if (x == null) return null;
        if (inst_proto.exists(x)) return inst_proto[x];
        o = __fw_rt::impl(x);
        if (o != null && o.kind == __FW_K_COMPONENT && conv_by_type.exists(o.tname)
            && conv_by_type[o.tname].is_xtor)
            return conv_by_type[o.tname].from;
        return null;
    endfunction

    static function fw_proto_role_e role_of(fw_object b);
        __fw_rt_obj o = __fw_rt::impl(b);
        if (o != null && o.kind == __FW_K_MIRROR) return FW_ROLE_TARGET;
        if (o != null && o.kind == __FW_K_MONITOR) return FW_ROLE_MONITOR;
        return FW_ROLE_INITIATOR;
    endfunction

    static function fw_component_ctor_q abstractors(fw_protocol_type p);
        fw_component_ctor_q q;
        __fw_rt_proto_rec r = rec(p);
        if (r != null)
            foreach (r.convs[i]) if (!r.convs[i].is_xtor) q.push_back(r.convs[i].ctor);
        return q;
    endfunction

    static function fw_ctor #(fw_component) abstractor_for(fw_protocol_type from, fw_protocol_type to);
        __fw_rt_proto_rec r = rec(from);
        if (r == null || to == null) return null;
        foreach (r.convs[i])
            if (!r.convs[i].is_xtor
                && ((r.convs[i].from == from && r.convs[i].to == to)
                    || (r.convs[i].from == to && r.convs[i].to == from)))
                return r.convs[i].ctor;
        return null;
    endfunction

    static function fw_protocol_type_q api_protocols(fw_api_type a);
        fw_protocol_type_q q;
        foreach (order[i]) if (order[i].req == a || order[i].rsp == a) q.push_back(order[i].h);
        return q;
    endfunction

    // ---- the netlist's "protocols" table ----

    static function string role_s(fw_proto_role_e r);
        case (r)
            FW_ROLE_TARGET:  return "target";
            FW_ROLE_MONITOR: return "monitor";
            default:         return "initiator";
        endcase
    endfunction

    // A transactor's role, from its pin mixin (not knowable at
    // `fw_xtor_utils`'s static registration time, since the mixin is an
    // instance field): a fw_mirror pin makes it the target, a fw_monitor
    // pin the monitor, a fw_bundle (driver) pin the initiator. Scans any
    // built instance of the transactor type for its top-level pin member.
    static function fw_proto_role_e xtor_role(string ty);
        foreach (__fw_rt::objs[i]) begin
            __fw_rt_obj o = __fw_rt::objs[i];
            if (o.kind == __FW_K_COMPONENT && o.tname == ty && !o.detached) begin
                foreach (o.children[j]) begin
                    __fw_rt_obj c = o.children[j];
                    if (c.kind == __FW_K_MIRROR) return FW_ROLE_TARGET;
                    if (c.kind == __FW_K_MONITOR) return FW_ROLE_MONITOR;
                    if (c.kind == __FW_K_BUNDLE) return FW_ROLE_INITIATOR;
                end
            end
        end
        return FW_ROLE_INITIATOR;
    endfunction

    // A parameter value as JSON: a number, else a string.
    static function string pval(string v);
        int k;
        if (v.len() != 0 && $sscanf(v, "%d", k) == 1 && $sformatf("%0d", k) == v) return v;
        return __fw_rt_str::jstr(v);
    endfunction

    // params keyed by position ("0", "1", ...): SV has the values of a
    // specialization's parameters but not their names (plan 8.10).
    static function string params_json(string n);
        string ps = params_of(n), r = "{", v = "";
        int depth = 0, k = 0;
        if (ps == "") return "{}";
        for (int i = 0; i <= ps.len(); i++) begin
            if (i == ps.len() || (depth == 0 && ps[i] == ",")) begin
                r = {r, k ? ", " : "", $sformatf("\"%0d\": ", k), pval(v)};
                k++;
                v = "";
                continue;
            end
            if (ps[i] == "(" || ps[i] == "[" || ps[i] == "{") depth++;
            if (ps[i] == ")" || ps[i] == "]" || ps[i] == "}") depth--;
            v = {v, ps[i]};
        end
        return {r, "}"};
    endfunction

    static function string rec_json(__fw_rt_proto_rec r);
        string s, cs[$], cj[string];
        s = {"{\"family\": ", __fw_rt_str::jstr(r.fam == null ? r.n : r.fam.n),
             ", \"params\": ", params_json(r.n),
             ", \"prefix\": ", __fw_rt_str::jstr(r.fam == null ? "" : r.fam.pfx), ", \"apis\": ["};
        if (r.req != null) s = {s, "{\"dir\": \"req\", \"type\": ", __fw_rt_str::jstr(api_names[r.req]), "}"};
        if (r.rsp != null) s = {s, r.req != null ? ", " : "", "{\"dir\": \"rsp\", \"type\": ",
                                __fw_rt_str::jstr(api_names[r.rsp]), "}"};
        s = {s, "], \"bundles\": ["};
        foreach (r.bundles[i]) s = {s, i ? ", " : "", __fw_rt_str::jstr(r.bundles[i])};
        s = {s, "], \"converters\": ["};
        foreach (r.convs[i]) begin
            __fw_rt_conv c = r.convs[i];
            __fw_rt_proto_rec f = rec(c.from), t = rec(c.to);
            string j = {"{\"type\": ", __fw_rt_str::jstr(c.ty),
                        ", \"from\": ", __fw_rt_str::jstr(f == null ? "" : f.n),
                        ", \"to\": ", __fw_rt_str::jstr(t == null ? "" : t.n)};
            if (c.is_xtor) j = {j, ", \"role\": \"", role_s(xtor_role(c.ty)), "\""};
            cj[c.ty] = {j, "}"};
            cs.push_back(c.ty);
        end
        cs.sort();
        foreach (cs[i]) s = {s, i ? ", " : "", cj[cs[i]]};
        return {s, "]}"};
    endfunction

    // The protocols the design uses: those of its sockets, its bundle
    // instances and its converter instances. Only when there are any.
    static function void write(int fd);
        __fw_rt_proto_rec used[string];
        string keys[$];
        foreach (__fw_rt::objs[i]) begin
            __fw_rt_obj o = __fw_rt::objs[i];
            if (o.aproto != "")
                foreach (order[j]) if (order[j].n == o.aproto) used[o.aproto] = order[j];
            if (o.kind == __FW_K_COMPONENT && conv_by_type.exists(o.tname)) begin
                __fw_rt_proto_rec f = rec(conv_by_type[o.tname].from), t = rec(conv_by_type[o.tname].to);
                if (f != null) used[f.n] = f;
                if (t != null) used[t.n] = t;
            end
        end
        foreach (used[k]) keys.push_back(k);
        if (keys.size() == 0) return;
        keys.sort();
        $fwrite(fd, ",\n  \"protocols\": {");
        foreach (keys[i])
            $fwrite(fd, "%s\n    %s: %s", i ? "," : "", __fw_rt_str::jstr(keys[i]), rec_json(used[keys[i]]));
        $fwrite(fd, "\n  }");
    endfunction
endclass

// An api or cfg binding, from the port (or inner) side to the export (or
// outer) side.
class __fw_rt_bind;
    string      kind;
    __fw_rt_obj from, to;
    __fw_rt_obj scope;          // the component whose connect() made it
endclass

// An export's implementation (set by create, or by set_imp).
class __fw_rt_imp #(type API = int);
    static API imp[__fw_rt_obj];
    static API memo[__fw_rt_obj];

    // A port's implementation: out along aup to an export, then in along
    // export connect_up chains to the export holding one; remembered. A
    // socket's OUT: out along connect_up to the socket with a peer, across
    // to the peer, then in along the peer's connect_up chain to its IN imp.
    static function API resolve(__fw_rt_obj p);
        __fw_rt_obj x = p;
        int n = 0;
        if (p == null) return null;
        if (memo.exists(p)) return memo[p];
        if (p.asock) begin
            while (x != null && x.apeer == null && n++ < __fw_rt::objs.size()) x = x.aup;
            if (x != null) x = x.apeer;
        end else
            while (x != null && x.aout && n++ < __fw_rt::objs.size()) x = x.aup;
        while (x != null && !imp.exists(x) && n++ < __fw_rt::objs.size()) begin
            __fw_rt_obj y = null;
            foreach (__fw_rt::objs[i])
                if (__fw_rt::objs[i].kind == __FW_K_API && __fw_rt::objs[i].asock == x.asock
                        && (x.asock || !__fw_rt::objs[i].aout)
                        && __fw_rt::objs[i].aup == x) y = __fw_rt::objs[i];
            x = y;
        end
        memo[p] = (x == null) ? null : imp[x];
        return memo[p];
    endfunction
endclass

// API endpoints and sockets: creation, bindings, and the connect-phase checks
// (protocols.md "Endpoints and sockets").
class __fw_rt_api;
    static __fw_rt_bind binds[$];

    // Records endpoint h: a port (out), an export, or a socket (both).
    static function __fw_rt_obj create(fw_object h, string name, fw_object parent, string raw,
                                       bit out, bit sock);
        __fw_rt_obj o = __fw_rt::new_obj(name, parent, __FW_K_API, raw, __FW_D_NONE, 0);
        __fw_rt::attach(h, o);
        o.aout = out;
        o.asock = sock;
        o.amust = out;
        return o;
    endfunction

    // a.connect(b) (up = 0) or a.connect_up(b) (up = 1); 1 when recorded.
    static function bit link(fw_object ha, fw_object hb, bit up);
        __fw_rt_obj a = __fw_rt::impl(ha), b = __fw_rt::impl(hb);
        __fw_rt_bind e;
        if (a == null || b == null) begin
            __fw_rt::diag("FW-E-ELAB-NEW", __fw_rt::cur_path(), "connection endpoint was not created by the factory");
            return 0;
        end
        if (a.detached || b.detached) return 0;
        if (__fw_rt::phase != __FW_P_CONNECT) begin
            __fw_rt::diag("FW-E-CONN-PHASE", a.path, "connection outside connect()");
            return 0;
        end
        if (!__fw_rt::in_scope(a)) begin
            __fw_rt::diag("FW-E-CONN-SCOPE", a.path, {"not in the scope of ", __fw_rt::cur.path});
            return 0;
        end
        if (!__fw_rt::in_scope(b)) begin
            __fw_rt::diag("FW-E-CONN-SCOPE", b.path, {"not in the scope of ", __fw_rt::cur.path});
            return 0;
        end
        if (a.aup != null || a.apeer != null) begin
            __fw_rt::diag("FW-E-SOCK-MULTI", a.path, {"already bound to ",
                a.aup != null ? a.aup.path : a.apeer.path});
            return 0;
        end
        if (a.asock && !up) begin
            // Socket to peer socket: linked both ways.
            if (b.aup != null || b.apeer != null) begin
                __fw_rt::diag("FW-E-SOCK-MULTI", b.path, {"already bound to ",
                    b.aup != null ? b.aup.path : b.apeer.path});
                return 0;
            end
            a.apeer = b;
            b.apeer = a;
        end else
            a.aup = b;
        e = new;
        e.kind = "api";
        e.from = a;
        e.to = b;
        e.scope = __fw_rt::cur;
        binds.push_back(e);
        return 1;
    endfunction

    // The crossing check of every api and cfg binding: the endpoints' domains are
    // their own associations, else their component's (domains.md, Lookup).
    static function void check_cross();
        foreach (binds[i]) begin
            __fw_rt_obj a[$], b[$];
            if (binds[i].kind != "api" && binds[i].kind != "cfg") continue;
            a.push_back(binds[i].from);
            b.push_back(binds[i].to);
            __fw_rt_dom::check_net(binds[i].scope, a, b);
        end
    endfunction

    // The end of the connect phase: every port side must reach an export.
    static function void check();
        foreach (__fw_rt::objs[i]) begin
            __fw_rt_obj o = __fw_rt::objs[i], x = o;
            int n = 0;
            if (o.kind != __FW_K_API || !o.amust) continue;
            if (o.asock) begin
                // The outermost socket of the connect_up chain must have a peer.
                while (x.apeer == null && x.aup != null && n++ < __fw_rt::objs.size()) x = x.aup;
                if (x.apeer != null) continue;
            end else begin
                while (x != null && x.aout && n++ < __fw_rt::objs.size()) x = x.aup;
                if (x != null && !x.aout) continue;
            end
            __fw_rt::diag("FW-E-SOCK-UNBOUND", o.path, "resolves to no export");
        end
    endfunction

    // The netlist's "bindings", when there are any; sorted by from, to, kind.
    static function void write(int fd);
        string keys[$];
        string js[string];
        foreach (binds[i]) begin
            string k = {binds[i].from.path, " ", binds[i].to.path, " ", binds[i].kind};
            if (js.exists(k)) continue;
            js[k] = {"{\"kind\": \"", binds[i].kind, "\", \"from\": ", __fw_rt_str::jstr(binds[i].from.path),
                     ", \"to\": ", __fw_rt_str::jstr(binds[i].to.path), "}"};
            keys.push_back(k);
        end
        if (keys.size() == 0) return;
        keys.sort();
        $fwrite(fd, ",\n  \"bindings\": [");
        foreach (keys[i]) $fwrite(fd, "%s\n    %s", i ? "," : "", js[keys[i]]);
        $fwrite(fd, "\n  ]");
    endfunction
endclass

typedef class __fw_rt_cfg;

// A configuration sink (protocols.md "Configuration"): a plain sink or a
// configured endpoint. The typed part is __fw_rt_cfg_t #(T), which also
// holds the sources' values.
virtual class __fw_rt_cfg_c;
    __fw_rt_obj o;
    __fw_rt_obj src;            // the source whose set() reaches it
    pure virtual function void push(__fw_rt_obj p);
endclass

virtual class __fw_rt_cfg_t #(type T = int) extends __fw_rt_cfg_c;
    static T   val[__fw_rt_obj];    // each source's last set()
    fw_cfg_listener_if #(T) ls[$];
    T          last;
    bit        pushed;

    pure virtual function T get_cfg();
    pure virtual function void put_cfg(T v);

    // Pushes p's value, if it has one, then calls the listeners. A copy
    // that differs from the last push was written by client code.
    virtual function void push(__fw_rt_obj p);
        if (!val.exists(p)) return;
        if (pushed && get_cfg() != last)
            __fw_rt::diag("FW-E-CFG-WRITE", o.path, "consumer cfg written by client code");
        put_cfg(val[p]);
        last = val[p];
        pushed = 1;
        foreach (ls[i]) ls[i].changed(val[p]);
    endfunction

    // A source's set(): store, then push to its sinks.
    static function void set(fw_object h, T v);
        __fw_rt_obj r = __fw_rt::impl(h);
        if (r == null) return;
        val[r] = v;
        __fw_rt_cfg::set(r);
    endfunction

    static function T get(fw_object h);
        __fw_rt_obj r = __fw_rt::impl(h);
        T v;
        if (r != null && val.exists(r)) v = val[r];
        return v;
    endfunction

    // A sink's add_listener().
    static function void listen(fw_object h, fw_cfg_listener_if #(T) l);
        __fw_rt_obj r = __fw_rt::impl(h);
        __fw_rt_cfg_t #(T) c;
        if (r == null || l == null || !__fw_rt_cfg::cmap.exists(r)) return;
        if ($cast(c, __fw_rt_cfg::cmap[r])) c.ls.push_back(l);
    endfunction
endclass

// The sink handle H, whose cfg field the push writes.
class __fw_rt_cfg_h #(type H = int, type T = int) extends __fw_rt_cfg_t #(T);
    H h;
    virtual function T get_cfg();
        return h.cfg;
    endfunction
    virtual function void put_cfg(T v);
        h.cfg = v;
    endfunction
endclass

// Sources, sinks and their binding: a sink reaches the source of the
// connect() at the end of its connect_up chain, then inward along the
// source's connect_up chain to the innermost source, whose set() it sees.
class __fw_rt_cfg;
    static bit          isrc[__fw_rt_obj];      // the sources
    static __fw_rt_cfg_c cons[$];
    static __fw_rt_cfg_c cmap[__fw_rt_obj];
    static __fw_rt_obj  cup[__fw_rt_obj];       // connect_up: inner -> outer
    static __fw_rt_obj  csrc[__fw_rt_obj];      // connect: sink side -> source side
    static bit          bound;                  // resolve() has run

    static function void source(__fw_rt_obj o);
        if (o != null) isrc[o] = 1;
    endfunction

    static function void sink(__fw_rt_obj o, __fw_rt_cfg_c c);
        if (o == null) return;
        c.o = o;
        cons.push_back(c);
        cmap[o] = c;
    endfunction

    static function void publisher(fw_object h, string name, fw_object parent, string raw);
        __fw_rt_obj o = __fw_rt::new_obj(name, parent, __FW_K_CFGP, raw, __FW_D_NONE, 0);
        __fw_rt::attach(h, o);
        source(o);
    endfunction

    static function void consumer(fw_object h, string name, fw_object parent, string raw,
                                  __fw_rt_cfg_c c);
        __fw_rt_obj o = __fw_rt::new_obj(name, parent, __FW_K_CFGC, raw, __FW_D_NONE, 0);
        __fw_rt::attach(h, o);
        sink(o, c);
    endfunction

    // A plain sink or source: a.connect(b) (up = 0) or a.connect_up(b) (up = 1).
    static function void link(fw_object ha, fw_object hb, bit up);
        __fw_rt_obj a = __fw_rt::impl(ha), b = __fw_rt::impl(hb);
        if (a == null || b == null) begin
            __fw_rt::diag("FW-E-ELAB-NEW", __fw_rt::cur_path(), "connection endpoint was not created by the factory");
            return;
        end
        if (a.detached || b.detached) return;
        if (__fw_rt::phase != __FW_P_CONNECT) begin
            __fw_rt::diag("FW-E-CONN-PHASE", a.path, "connection outside connect()");
            return;
        end
        if (!__fw_rt::in_scope(a)) begin
            __fw_rt::diag("FW-E-CONN-SCOPE", a.path, {"not in the scope of ", __fw_rt::cur.path});
            return;
        end
        if (!__fw_rt::in_scope(b)) begin
            __fw_rt::diag("FW-E-CONN-SCOPE", b.path, {"not in the scope of ", __fw_rt::cur.path});
            return;
        end
        bind_cfg(a, b, up);
    endfunction

    // Records a checked cfg connection and its "cfg" binding, source to sink.
    static function void bind_cfg(__fw_rt_obj a, __fw_rt_obj b, bit up);
        __fw_rt_bind e = new;
        if (up) begin
            cup[a] = b;
            e.from = isrc.exists(a) ? a : b;
            e.to = isrc.exists(a) ? b : a;
        end else begin
            __fw_rt_obj s = isrc.exists(a) ? b : a, p = isrc.exists(a) ? a : b;
            if (csrc.exists(s)) begin
                __fw_rt::diag("FW-E-SOCK-MULTI", s.path, {"already configured by ", csrc[s].path});
                return;
            end
            csrc[s] = p;
            e.from = p;
            e.to = s;
        end
        e.kind = "cfg";
        e.scope = __fw_rt::cur;
        __fw_rt_api::binds.push_back(e);
    endfunction

    // The end of the connect phase: bind each sink to its source and push.
    static function void resolve();
        int n = __fw_rt::objs.size();
        bit outer[__fw_rt_obj];
        foreach (cons[i]) if (cup.exists(cons[i].o)) outer[cup[cons[i].o]] = 1;
        foreach (cons[i]) begin
            __fw_rt_cfg_c c = cons[i];
            __fw_rt_obj x = c.o, s;
            int k = 0;
            bit more = 1;
            while (!csrc.exists(x) && cup.exists(x) && k++ < n) x = cup[x];
            if (!csrc.exists(x)) begin
                if (!outer.exists(c.o)) __fw_rt::diag("FW-E-CFG-UNBOUND", c.o.path, "no source reaches this sink");
                continue;
            end
            s = csrc[x];
            while (more && k++ < n) begin
                more = 0;
                foreach (cup[y]) if (cup[y] == s && isrc.exists(y)) begin
                    s = y;
                    more = 1;
                    break;
                end
            end
            c.src = s;
            c.push(s);
        end
        bound = 1;
    endfunction

    // A source's set(): push to the sinks it reaches.
    static function void set(__fw_rt_obj p);
        if (!bound) return;
        foreach (cons[i]) if (cons[i].src == p) cons[i].push(p);
    endfunction
endclass
