// fw_rt.svh: the rt-sv elaboration runtime. Included inside fw_hdl_pkg,
// after the spec's fw_hdl_api.svh.
//
// Every name here begins __fw_ (reserved for the API and its tools). The
// runtime's state for an API object is an __fw_rt_obj, stored in
// fw_object::__fw_impl. Semantics: fw-hdl-spec semantics/*.md.
//
// The phase walk and naming are ported from the fw-hdl reference code's
// fw_component (core-layer1.md 8), rewritten for the layer-1 API.

typedef class __fw_rt;
typedef class __fw_rt_dom;
typedef class __fw_rt_proto;
typedef class __fw_rt_api;
typedef class __fw_rt_cfg;
typedef class __fw_rt_held_base;
typedef class __fw_rt_net;
typedef class __fw_rt_val;
typedef class __fw_rt_cell;
typedef class __fw_rt_procs;
typedef class __fw_rt_kern;

typedef enum int {
    __FW_K_COMPONENT, __FW_K_SIGNAL, __FW_K_PORT,
    __FW_K_BUNDLE, __FW_K_MIRROR, __FW_K_MONITOR, __FW_K_DOMAIN, __FW_K_API,
    __FW_K_CFGP, __FW_K_CFGC
} __fw_rt_kind_e;

typedef enum int { __FW_D_NONE, __FW_D_IN, __FW_D_OUT, __FW_D_INOUT } __fw_rt_dir_e;

typedef enum int {
    __FW_P_PRE, __FW_P_BUILD, __FW_P_CONNECT, __FW_P_RESOLVE, __FW_P_DONE
} __fw_rt_phase_e;

// Endpoint roles within a scope (connections.md).
localparam int __FW_R_SRC   = 1;
localparam int __FW_R_SNK   = 2;
localparam int __FW_R_INOUT = 4;
localparam int __FW_R_SIG   = 8;

// The runtime's record of one structural object.
class __fw_rt_obj implements fw_impl_if;
    string          name;
    string          path;
    __fw_rt_kind_e  kind;
    string          tname;          // canonical type spelling
    __fw_rt_dir_e   dir;            // declared direction (ports)
    int             width;
    int             seq;            // creation order
    __fw_rt_obj     parent;
    __fw_rt_obj     children[$];    // creation order
    fw_object       h;
    bit             detached;       // not in the tree (after an error)

    // Components with params of their own.
    bit             has_params;
    string          ptype;          // raw $typename of params_t
    __fw_rt_field   pfields[$];     // value before init
    string          psrc[string];   // field -> source
    string          params_json = "{}";
    string          src_json = "{}";
    string          ext_json;       // externs: the "extern" record

    // Domains (domains.md). Keys of the per-object tables are
    // "<kind name>/<association name>".
    __fw_rt_obj     assoc[string];  // associations set on this object
    bit             aread[string];  // named associations read by get
    string          pnames[string]; // components: port_name()
    string          provs[string];  // components: provides(), params JSON
    fw_domain_kind_type dkind;      // a domain: its kind
    __fw_rt_held_base   dheld;      // a domain: its params, typed
    __fw_rt_obj     dfrom[$];       // a domain: its sources
    __fw_rt_obj     dclock;         // a reset domain: its clock
    __fw_rt_field   dfields[$];     // a domain: its params, as JSON fields
    string          dparams_json = "{}";
    string          drv_keys[$];    // a domain: its drivers' sort keys
    string          drv_json[$];    //   and their JSON, in call order
    bit             realized;       // a domain: a pin or driver uses it
    __fw_rt_obj     dsig;           // a domain: its driver signal, if any
    bit             dlow;           //   and the driver's active_low

    // Values (processes.md): a signal's net, set after resolve.
    __fw_rt_net     net;
    __fw_rt_obj     sclk;           // a signal: its clock domain (lazy)
    bit             sclk_done;
    __fw_rt_cell    dpend[$];       // a clock domain: register writes for its commit
    int             dedges;         //   and its edges so far (for tick)

    // API endpoints and sockets (protocols.md).
    string          aproto;         // a socket or bundle instance: its protocol's name
    bit             aout;           // a bare port or a socket (has an OUT side)
    bit             asock;          // a socket
    bit             amust;          // has a port side that must be bound
    __fw_rt_obj     aup;            // bound to (port connect, or connect_up)
    __fw_rt_obj     apeer;          // a socket: the peer socket (connect, both ways)

    function bit is_signal();
        return kind == __FW_K_SIGNAL || kind == __FW_K_PORT;
    endfunction

    function bit is_bundle();
        return kind == __FW_K_BUNDLE || kind == __FW_K_MIRROR || kind == __FW_K_MONITOR;
    endfunction

    // The component that owns this object.
    function __fw_rt_obj scope();
        __fw_rt_obj o = parent;
        while (o != null && o.kind != __FW_K_COMPONENT) o = o.parent;
        return o;
    endfunction

    // The direction seen from the scope: flipped by each mirror on the path,
    // an input below any monitor; inout stays inout.
    function __fw_rt_dir_e eff_dir();
        __fw_rt_dir_e d = dir;
        if (kind != __FW_K_PORT || d == __FW_D_INOUT) return d;
        for (__fw_rt_obj o = parent; o != null && o.kind != __FW_K_COMPONENT; o = o.parent)
            if (o.kind == __FW_K_MONITOR) return __FW_D_IN;
        for (__fw_rt_obj o = parent; o != null && o.kind != __FW_K_COMPONENT; o = o.parent)
            if (o.kind == __FW_K_MIRROR) d = (d == __FW_D_IN) ? __FW_D_OUT : __FW_D_IN;
        return d;
    endfunction

    // The path relative to ancestor a ("in.valid").
    function string rel(__fw_rt_obj a);
        return path.substr(a.path.len() + 1, path.len() - 1);
    endfunction

    // The leaf signals and ports below a component or bundle, in creation
    // order, not descending into child components.
    function void leaves(ref __fw_rt_obj out[$]);
        foreach (children[i]) begin
            if (children[i].is_signal()) out.push_back(children[i]);
            else if (children[i].is_bundle()) children[i].leaves(out);
        end
    endfunction

    function string kind_s();
        case (kind)
            __FW_K_COMPONENT: return "component";
            __FW_K_SIGNAL:    return "signal";
            __FW_K_PORT:      return "port";
            __FW_K_BUNDLE:    return "bundle";
            __FW_K_MIRROR:    return "mirror";
            __FW_K_MONITOR:   return "monitor";
            __FW_K_API:       return "api_endpoint";
            __FW_K_CFGP:      return "cfg_src";
            __FW_K_CFGC:      return "cfg_sink";
            default:          return "domain";
        endcase
    endfunction

    function string dir_s();
        case (eff_dir())
            __FW_D_IN:  return "in";
            __FW_D_OUT: return "out";
            default:    return "inout";
        endcase
    endfunction

    function string json();
        string r = $sformatf("{\"path\": %s, \"kind\": \"%s\"", __fw_rt_str::jstr(path), kind_s());
        r = {r, ", \"type\": ", __fw_rt_str::jstr(tname)};
        if (kind == __FW_K_DOMAIN) r = {r, ", \"params\": ", dparams_json};
        if (kind == __FW_K_PORT) r = {r, ", \"dir\": \"", dir_s(), "\""};
        if (aproto != "") r = {r, ", \"protocol\": ", __fw_rt_str::jstr(aproto)};
        if (aproto != "" && is_bundle())
            r = {r, ", \"role\": \"", kind == __FW_K_MIRROR ? "target" : kind == __FW_K_MONITOR ? "monitor" : "initiator", "\""};
        if (is_signal()) r = {r, $sformatf(", \"width\": %0d", width)};
        if (kind == __FW_K_COMPONENT) begin
            r = {r, ", \"params\": ", params_json, ", \"param_src\": ", src_json};
            if (ext_json != "") r = {r, ", \"extern\": ", ext_json};
        end
        return {r, __fw_rt_dom::json(this), "}"};
    endfunction
endclass

// Reaches fw_object::__fw_impl for the runtime. Never instantiated.
virtual class __fw_rt_acc extends fw_object;
    static function __fw_rt_obj get(fw_object h);
        __fw_rt_obj o;
        if (h == null || h.__fw_impl == null) return null;
        void'($cast(o, h.__fw_impl));
        return o;
    endfunction
    static function void set(fw_object h, __fw_rt_obj o);
        h.__fw_impl = o;
    endfunction
endclass

// A connection or tie recorded in a scope, at signal level.
class __fw_rt_conn;
    __fw_rt_obj scope;
    __fw_rt_obj a, b;       // b is null for a tie
    string      tie;
endclass

// A params override. The typed part is __fw_rt_ov_t #(P).
virtual class __fw_rt_ov;
    __fw_rt_obj scope;      // null: global
    string      glob;
    string      ptype;
    int         seq;
    bit         matched;
endclass

class __fw_rt_ov_t #(type P = int) extends __fw_rt_ov;
    static __fw_rt_ov_t #(P) q[$];
    P                  value;
    fw_param_edit #(P) e;
    function P apply(P p);
        if (e != null) return e.apply(p);
        return value;
    endfunction
endclass

// Pending creator values, one stack per params type.
class __fw_rt_box #(type P = int);
    static P q[$];
    static function void push(P p);
        q.push_back(p);
    endfunction
    static function void pop();
        void'(q.pop_back());
    endfunction
endclass

// One entry of an extern map, in call order.
class __fw_rt_xm_ent;
    bit          is_rule;
    string       pin;          // pin(): the pin; rule: the prefix
    __fw_rt_obj  obj;          // the port, or the rule's bundle
    fw_pin_rule  r;
    string       ren[string];  // member path -> pin part
endclass

// A module parameter value made by fw_value::of or fw_type::get, already
// spelled for the netlist (extern.params: its type and its value). The
// spelling is computed where T is known; xm_param reads it through this
// interface.
interface class __fw_rt_parg_if;
    pure virtual function string __fw_ty();
    pure virtual function string __fw_val();
endclass

// What fw_value #(T)::of returns.
class __fw_rt_value #(type T = int) extends fw_value #(T) implements __fw_rt_parg_if;
    string ty;
    string val;
    virtual function string __fw_ty(); return ty; endfunction
    virtual function string __fw_val(); return val; endfunction
endclass

// What fw_type #(T)::get returns (one per T).
class __fw_rt_type #(type T = int) extends fw_type #(T) implements __fw_rt_parg_if;
    string val;
    virtual function string __fw_ty(); return "type"; endfunction
    virtual function string __fw_val(); return val; endfunction
endclass

// A class whose $typename shows the layout of a packed struct T: Verilator
// spells a struct value parameter as "'{4'h0,'{..},32'sh0}", one sized
// literal (width, signedness) per member, MSB first in declaration order.
class __fw_rt_shape #(type T = int, T V = T'(0));
endclass

// A domain pin of an extern map: pin() or pin_out() of fw_domain.
class __fw_rt_dpin;
    string       pin;
    string       kname;
    __fw_rt_obj  dom;          // null: resolved to none
    bit          out;
    string       attr;         // JSON
endclass

// The extern map being filled.
class __fw_rt_xm;
    __fw_rt_obj     comp;
    string          pnames[$];
    string          ptypes[string];
    string          pvals[string];
    __fw_rt_xm_ent  ents[$];
    string          ties[$];
    string          tie_vals[string];
    string          opens[$];
    __fw_rt_obj     unused[$];
    __fw_rt_dpin    dpins[$];
endclass

class __fw_rt_diag;
    string id;
    string path;
endclass

// Resolves a component's params value; called from the params macros, in the
// constructor of the class that declares params_t.
class __fw_rt_params #(type P = int);

    static function void diff(__fw_rt_obj o, __fw_rt_field a[$], __fw_rt_field b[$], string src);
        foreach (b[i])
            if (i < a.size() && a[i].json != b[i].json) o.psrc[b[i].name] = src;
    endfunction

    static function void parse(string text, ref __fw_rt_field out[$]);
        __fw_rt_pj pj = new;
        pj.ctors = __fw_rt::ctors;
        pj.fields(text, out);
    endfunction

    static function bit ov_before(__fw_rt_ov a, __fw_rt_ov b);
        if ((a.scope == null) != (b.scope == null)) return a.scope != null;
        if (a.scope != null && a.scope.path.len() != b.scope.path.len())
            return a.scope.path.len() > b.scope.path.len();
        return a.seq < b.seq;
    endfunction

    // Sources 1-4: defaults, creator, overrides (nearest ancestor first),
    // global overrides.
    static function P resolve(P dflt);
        __fw_rt_obj o = __fw_rt::pending();
        P p = dflt;
        __fw_rt_field f0[$], f1[$];
        __fw_rt_ov_t #(P) ovs[$];
        if (o == null) begin
            __fw_rt::diag("FW-E-ELAB-NEW", __fw_rt::cur_path(), "component constructed without the factory");
            return dflt;
        end
        if (__fw_rt_box #(P)::q.size() > 0) p = __fw_rt_box #(P)::q[$];
        o.has_params = 1;
        o.ptype = $typename(P);
        parse($sformatf("%p", dflt), f0);
        parse($sformatf("%p", p), f1);
        diff(o, f0, f1, "creator");
        if (!o.detached) begin
            foreach (__fw_rt_ov_t #(P)::q[i])
                if (__fw_rt::ov_matches(__fw_rt_ov_t #(P)::q[i], o.path))
                    ovs.push_back(__fw_rt_ov_t #(P)::q[i]);
            for (int i = 1; i < ovs.size(); i++)
                for (int j = i; j > 0 && ov_before(ovs[j], ovs[j-1]); j--) begin
                    __fw_rt_ov_t #(P) t = ovs[j];
                    ovs[j] = ovs[j-1];
                    ovs[j-1] = t;
                end
            foreach (ovs[i]) begin
                ovs[i].matched = 1;
                f0 = f1;
                p = ovs[i].apply(p);
                parse($sformatf("%p", p), f1);
                diff(o, f0, f1, ovs[i].scope == null ? "global" : "override");
            end
        end
        o.pfields = f1;
        return p;
    endfunction

    // Source 5, the init function, has run: record the value.
    static function void finish(P p);
        __fw_rt_obj o = __fw_rt::pending();
        __fw_rt_field f[$];
        string pj = "{", sj = "{";
        bit first = 1;
        if (o == null) return;
        parse($sformatf("%p", p), f);
        diff(o, o.pfields, f, "init");
        foreach (f[i]) begin
            if (i) pj = {pj, ", "};
            pj = {pj, __fw_rt_str::jstr(f[i].name), ": ", f[i].json};
            if (o.psrc.exists(f[i].name)) begin
                if (!first) sj = {sj, ", "};
                sj = {sj, __fw_rt_str::jstr(f[i].name), ": \"", o.psrc[f[i].name], "\""};
                first = 0;
            end
        end
        o.params_json = {pj, "}"};
        o.src_json = {sj, "}"};
    endfunction

endclass

// The runtime: all state is static; one elaboration per simulation.
class __fw_rt;
    static __fw_rt_phase_e phase = __FW_P_PRE;
    static __fw_rt_obj     top;
    static __fw_rt_obj     cur;           // the component whose phase method runs
    static __fw_rt_obj     ctx[$];        // components being constructed
    static __fw_rt_obj     objs[$];       // in the tree, creation order
    static int             nseq;
    static __fw_rt_diag    diags[$];
    static __fw_rt_conn    conns[$];
    static __fw_rt_ov      ovs[$];
    static string          ctors[string]; // %p handle name -> realization type
    static __fw_rt_xm      xm;

    static function void diag(string id, string path, string msg);
        __fw_rt_diag d = new;
        d.id = id;
        d.path = path;
        diags.push_back(d);
        $display("%s: %s: %s", id, path, msg);
    endfunction

    static function string cur_path();
        if (cur != null) return cur.path;
        if (ctx.size() > 0) return ctx[$].path;
        return "";
    endfunction

    static function __fw_rt_obj pending();
        if (ctx.size() == 0) return null;
        return ctx[$];
    endfunction

    static function void reg_ctor(string p, string raw);
        // p is "'{h:<handle name>}"
        int i = 0;
        string n;
        while (i < p.len() && p[i] != ":") i++;
        n = p.substr(i + 1, p.len() - 2);
        ctors[n] = __fw_rt_str::tn(raw);
    endfunction

    // The runtime record of h. A component under construction has no record
    // in its handle yet: the record of the innermost pending creation is
    // attached on first use.
    static function __fw_rt_obj impl(fw_object h);
        __fw_rt_obj o = __fw_rt_acc::get(h);
        if (o != null || h == null) return o;
        if (ctx.size() > 0 && ctx[$].h == null) begin
            o = ctx[$];
            o.h = h;
            __fw_rt_acc::set(h, o);
        end
        return o;
    endfunction

    static function bit legal_name(string n);
        int i = 0;
        if (n.len() == 0 || !__fw_rt_str::is_id_start(n[0])) return 0;
        while (i < n.len() && __fw_rt_str::is_id_char(n[i])) i++;
        while (i < n.len()) begin
            int j;
            if (n[i] != "[") return 0;
            j = i + 1;
            while (j < n.len() && __fw_rt_str::is_digit(n[j])) j++;
            if (j == i + 1 || j >= n.len() || n[j] != "]") return 0;
            i = j + 1;
        end
        return 1;
    endfunction

    // A new record named name under parent. Detached after an error.
    static function __fw_rt_obj new_obj(string name, fw_object parent, __fw_rt_kind_e kind,
                                        string raw_type, __fw_rt_dir_e dir, int width);
        __fw_rt_obj o = new;
        __fw_rt_obj p;
        o.name = name;
        o.kind = kind;
        o.tname = __fw_rt_str::tn(raw_type);
        o.dir = dir;
        o.width = width;
        o.path = name;
        if (parent == null) begin
            if (top == null && kind == __FW_K_COMPONENT) begin
                top = o;
                o.seq = nseq++;
                objs.push_back(o);
            end else begin
                o.detached = 1;
                diag("FW-E-ELAB-NEW", cur_path(), {"object '", name, "' has no parent"});
            end
            return o;
        end
        p = impl(parent);
        if (p == null) begin
            o.detached = 1;
            diag("FW-E-ELAB-NEW", cur_path(), {"parent of '", name, "' was not created by the factory"});
            return o;
        end
        o.path = {p.path, ".", name};
        o.parent = p;
        if (p.detached) begin
            o.detached = 1;
            return o;
        end
        if (phase > __FW_P_BUILD) begin
            o.detached = 1;
            diag("FW-E-ELAB-LATE", o.path, "created after the build phase");
            return o;
        end
        if (!legal_name(name)) begin
            o.detached = 1;
            diag("FW-E-NAME-BAD", o.path, "not a legal name");
            return o;
        end
        foreach (p.children[i])
            if (p.children[i].name == name) begin
                o.detached = 1;
                diag("FW-E-NAME-DUP", o.path, "duplicate name");
                return o;
            end
        p.children.push_back(o);
        o.seq = nseq++;
        objs.push_back(o);
        return o;
    endfunction

    static function void attach(fw_object h, __fw_rt_obj o);
        o.h = h;
        __fw_rt_acc::set(h, o);
    endfunction

    // `fw_component_utils: around the constructor.
    static function void begin_comp(string name, fw_component parent, string raw_type);
        if (phase == __FW_P_PRE) phase = __FW_P_BUILD;
        ctx.push_back(new_obj(name, parent, __FW_K_COMPONENT, raw_type, __FW_D_NONE, 0));
    endfunction

    static function void end_comp(fw_component c);
        __fw_rt_obj o = ctx.pop_back();
        if (o.h == null) attach(c, o);
    endfunction

    // ---- overrides ----

    static function bit wild(string pat, string s);
        if (pat.len() == 0) return s.len() == 0;
        if (pat[0] == "*") begin
            for (int k = 0; k <= s.len(); k++)
                if (wild(pat.substr(1, pat.len() - 1), k == s.len() ? "" : s.substr(k, s.len() - 1)))
                    return 1;
            return 0;
        end
        if (s.len() == 0 || pat[0] != s[0]) return 0;
        return wild(pat.substr(1, pat.len() - 1), s.substr(1, s.len() - 1));
    endfunction

    static function void split(string s, ref string out[$]);
        int st = 0;
        out.delete();
        for (int i = 0; i <= s.len(); i++)
            if (i == s.len() || s[i] == ".") begin
                out.push_back(i > st ? s.substr(st, i - 1) : "");
                st = i + 1;
            end
    endfunction

    static function bit segs(string g[$], int gi, string p[$], int pi);
        if (gi == g.size()) return pi == p.size();
        if (g[gi] == "**") begin
            for (int k = pi; k <= p.size(); k++)
                if (segs(g, gi + 1, p, k)) return 1;
            return 0;
        end
        if (pi == p.size() || !wild(g[gi], p[pi])) return 0;
        return segs(g, gi + 1, p, pi + 1);
    endfunction

    static function bit glob_match(string glob, string path);
        string g[$], p[$];
        split(glob, g);
        split(path, p);
        return segs(g, 0, p, 0);
    endfunction

    static function bit ov_matches(__fw_rt_ov ov, string path);
        string pre;
        if (ov.scope == null) return glob_match(ov.glob, path);
        pre = {ov.scope.path, "."};
        if (path.len() <= pre.len() || path.substr(0, pre.len() - 1) != pre) return 0;
        return glob_match(ov.glob, path.substr(pre.len(), path.len() - 1));
    endfunction

    static function void add_ov(__fw_rt_ov ov, fw_component scope, string glob, string ptype);
        ov.glob = glob;
        ov.ptype = ptype;
        ov.seq = ovs.size();
        if (scope != null) begin
            ov.scope = impl(scope);
            if (ov.scope == null) begin
                diag("FW-E-ELAB-NEW", cur_path(), "override scope was not created by the factory");
                return;
            end
        end
        ovs.push_back(ov);
        foreach (objs[i])
            if (objs[i].kind == __FW_K_COMPONENT && objs[i].has_params && objs[i].ptype == ptype
                    && ov_matches(ov, objs[i].path)) begin
                ov.matched = 1;
                diag("FW-E-PARAM-LATE", objs[i].path, {"override '", glob, "' registered after its target was created"});
            end
    endfunction

    // ---- connections ----

    static function bit in_scope(__fw_rt_obj o);
        __fw_rt_obj sc = o.scope();
        if (sc == cur) return 1;
        return sc != null && sc.parent == cur && o.kind != __FW_K_SIGNAL;
    endfunction

    static function void record(__fw_rt_obj a, __fw_rt_obj b);
        __fw_rt_conn c = new;
        c.scope = cur;
        c.a = a;
        c.b = b;
        conns.push_back(c);
    endfunction

    static function void expand(__fw_rt_obj a, __fw_rt_obj b);
        foreach (a.children[i]) begin
            __fw_rt_obj m = a.children[i];
            foreach (b.children[j])
                if (b.children[j].name == m.name) begin
                    if (m.is_bundle()) expand(m, b.children[j]);
                    else record(m, b.children[j]);
                end
        end
    endfunction

    static function void connect(fw_object ha, fw_object hb);
        __fw_rt_obj a = impl(ha), b = impl(hb);
        if (a == null || b == null) begin
            diag("FW-E-ELAB-NEW", cur_path(), "connection endpoint was not created by the factory");
            return;
        end
        if (a.detached || b.detached) return;
        if (phase != __FW_P_CONNECT) begin
            diag("FW-E-CONN-PHASE", a.path, "connection outside connect()");
            return;
        end
        if (!(a.is_signal() && b.is_signal()) && !(a.is_bundle() && b.is_bundle())) begin
            diag("FW-E-CONN-TYPE", a.path, {"cannot connect a ", a.kind_s(), " to a ", b.kind_s()});
            return;
        end
        if (a.tname != b.tname) begin
            diag("FW-E-CONN-TYPE", a.path, {"type ", a.tname, " is not ", b.tname, " (", b.path, ")"});
            return;
        end
        if (!in_scope(a)) begin
            diag("FW-E-CONN-SCOPE", a.path, {"not in the scope of ", cur.path});
            return;
        end
        if (!in_scope(b)) begin
            diag("FW-E-CONN-SCOPE", b.path, {"not in the scope of ", cur.path});
            return;
        end
        if (a.is_bundle()) begin
            expand(a, b);
        end else record(a, b);
    endfunction

    static function void tie(fw_object h, string value);
        __fw_rt_obj a = impl(h);
        __fw_rt_conn c;
        if (a == null) begin
            diag("FW-E-ELAB-NEW", cur_path(), "tied object was not created by the factory");
            return;
        end
        if (a.detached) return;
        if (phase != __FW_P_CONNECT) begin
            diag("FW-E-CONN-PHASE", a.path, "tie outside connect()");
            return;
        end
        if (!in_scope(a)) begin
            diag("FW-E-CONN-SCOPE", a.path, {"not in the scope of ", cur.path});
            return;
        end
        c = new;
        c.scope = cur;
        c.a = a;
        c.tie = value;
        conns.push_back(c);
    endfunction

    // ---- extern maps ----

    static function void xm_param(string name, fw_param_arg value);
        __fw_rt_parg_if a;
        if (value == null || !$cast(a, value)) begin
            diag("FW-E-EXT-PARAM", xm.comp != null ? xm.comp.path : cur_path(),
                 {"parameter '", name, "': no value (use fw_value::of or fw_type::get)"});
            return;
        end
        if (!xm.pvals.exists(name)) xm.pnames.push_back(name);
        xm.ptypes[name] = a.__fw_ty();
        xm.pvals[name] = a.__fw_val();
    endfunction

    static function void xm_pin(string name, fw_signal_base s);
        __fw_rt_xm_ent e = new;
        e.pin = name;
        e.obj = impl(s);
        xm.ents.push_back(e);
    endfunction

    static function void xm_rule(fw_pin_rule r, fw_object b, string pre);
        __fw_rt_xm_ent e = new;
        e.is_rule = 1;
        e.pin = pre;
        e.obj = impl(b);
        e.r = r;
        xm.ents.push_back(e);
    endfunction

    static function void xm_rename(fw_pin_rule r, string member, string part);
        foreach (xm.ents[i])
            if (xm.ents[i].r == r) xm.ents[i].ren[member] = part;
    endfunction

    static function void xm_tie(string name, string value);
        xm.ties.push_back(name);
        xm.tie_vals[name] = value;
    endfunction

    static function void xm_open(string name);
        xm.opens.push_back(name);
    endfunction

    static function void xm_unused(fw_object h);
        xm.unused.push_back(impl(h));
    endfunction

    static function void do_extern(__fw_rt_obj o, fw_extern_if x);
        __fw_rt_obj lv[$];
        string pin_of[string];     // port rel path -> pin
        string pins[$];            // every pin used, for the duplicate check
        string keys[$];
        int    seen[string];
        string r;
        fw_extern_map m = new;
        string pin_port[string];
        int    unused_rp[string];  // unused(): leaf port rel path (extern.md rule 5)
        string fld_of[string][string]; // field-wise leaf rel path -> pin -> field path (extern.md rule 2)
        xm = new;
        xm.comp = o;
        x.extern_map(m);
        o.leaves(lv);
        foreach (xm.unused[i]) begin
            __fw_rt_obj u = xm.unused[i];
            __fw_rt_obj ul[$];
            if (u == null || u.detached) continue;
            if (u.scope() != o || !(u.kind == __FW_K_PORT || u.is_bundle())) begin
                diag("FW-E-EXT-PORT", u.path, {"unused() names an object that is not a port or bundle of ", o.path});
                continue;
            end
            if (u.is_bundle()) u.leaves(ul);
            else ul.push_back(u);
            foreach (ul[k]) begin
                if (ul[k].eff_dir() != __FW_D_IN)
                    diag("FW-E-EXT-PORT", ul[k].path, "an output or inout port cannot be unused");
                unused_rp[ul[k].rel(o)] = 1;
            end
        end
        foreach (xm.ents[i]) begin
            __fw_rt_xm_ent e = xm.ents[i];
            if (e.obj == null || e.obj.detached) continue;
            if (!e.is_rule) begin
                if (e.obj.scope() != o || !e.obj.is_signal()) begin
                    diag("FW-E-EXT-PORT", e.obj.path, {"pin '", e.pin, "' maps an object that is not a port of ", o.path});
                    continue;
                end
                if (unused_rp.exists(e.obj.rel(o))) begin
                    diag("FW-E-EXT-PORT", e.obj.path, {"both unused and mapped to pin '", e.pin, "'"});
                    continue;
                end
                pin_of[e.obj.rel(o)] = e.pin;
                if (fld_of.exists(e.obj.rel(o))) fld_of.delete(e.obj.rel(o));   // whole wins
            end else begin
                __fw_rt_obj m[$];
                e.obj.leaves(m);
                foreach (m[k]) begin
                    string mr = m[k].rel(e.obj);
                    bit    fw = 0;
                    if (pin_of.exists(m[k].rel(o)) || unused_rp.exists(m[k].rel(o))) continue;
                    // a rename path into the member maps it field-wise; only
                    // the renamed fields are known here (no type reflection)
                    foreach (e.ren[p])
                        if (p.len() > mr.len() + 1 && p.substr(0, mr.len()) == {mr, "."}) begin
                            fld_of[m[k].rel(o)][{e.pin, e.ren[p]}] = p.substr(mr.len() + 1, p.len() - 1);
                            fw = 1;
                        end
                    if (fw) continue;
                    pin_of[m[k].rel(o)] = {e.pin, e.ren.exists(mr) ? e.ren[mr]
                                                 : __fw_rt_str::replace_char(mr, ".", "_")};
                end
            end
        end
        foreach (lv[i]) begin
            string rp = lv[i].rel(o);
            if (unused_rp.exists(rp)) continue;
            if (fld_of.exists(rp)) begin
                foreach (fld_of[rp][p]) pins.push_back(p);
                continue;
            end
            if (!pin_of.exists(rp)) pin_of[rp] = __fw_rt_str::replace_char(rp, ".", "_");
            pins.push_back(pin_of[rp]);
        end
        foreach (xm.ties[i]) pins.push_back(xm.ties[i]);
        foreach (xm.opens[i]) pins.push_back(xm.opens[i]);
        foreach (xm.dpins[i]) pins.push_back(xm.dpins[i].pin);
        foreach (pins[i]) begin
            if (seen.exists(pins[i])) diag("FW-E-EXT-PIN", o.path, {"pin '", pins[i], "' mapped twice"});
            seen[pins[i]] = 1;
        end
        // the record
        r = {"{\"module\": ", __fw_rt_str::jstr(x.extern_module()), ", \"params\": {"};
        keys = xm.pnames;
        keys.sort();
        foreach (keys[i]) r = {r, i ? ", " : "", __fw_rt_str::jstr(keys[i]),
                              ": {\"type\": ", __fw_rt_str::jstr(xm.ptypes[keys[i]]),
                              ", \"value\": ", __fw_rt_str::jstr(xm.pvals[keys[i]]), "}"};
        r = {r, "}, \"pins\": {"};
        foreach (lv[i]) begin
            string rp = lv[i].rel(o);
            if (unused_rp.exists(rp)) continue;
            if (fld_of.exists(rp)) begin
                foreach (fld_of[rp][p])
                    if (!pin_port.exists(p)) pin_port[p] = {rp, ".", fld_of[rp][p]};
            end else if (!pin_port.exists(pin_of[rp])) pin_port[pin_of[rp]] = rp;
        end
        keys.delete();
        foreach (pin_port[k]) keys.push_back(k);
        foreach (keys[i]) r = {r, i ? ", " : "", __fw_rt_str::jstr(keys[i]), ": ", __fw_rt_str::jstr(pin_port[keys[i]])};
        r = {r, "}, \"ties\": {"};
        keys = xm.ties;
        keys.sort();
        foreach (keys[i]) r = {r, i ? ", " : "", __fw_rt_str::jstr(keys[i]), ": ", __fw_rt_str::jstr(xm.tie_vals[keys[i]])};
        r = {r, "}, \"open\": ["};
        keys = xm.opens;
        keys.sort();
        foreach (keys[i]) r = {r, i ? ", " : "", __fw_rt_str::jstr(keys[i])};
        r = {r, "], \"unused\": ["};
        keys.delete();
        foreach (unused_rp[k]) keys.push_back(k);   // an associative array iterates sorted
        foreach (keys[i]) r = {r, i ? ", " : "", __fw_rt_str::jstr(keys[i])};
        o.ext_json = {r, "]", __fw_rt_dom::dpins_json(xm.dpins), "}"};
    endfunction

    // ---- resolution ----

    static function int role(__fw_rt_obj s, __fw_rt_obj o);
        __fw_rt_dir_e d = o.eff_dir();
        if (o.kind == __FW_K_SIGNAL) return __FW_R_SIG;
        if (d == __FW_D_INOUT) return __FW_R_INOUT;
        if (o.scope() == s) return d == __FW_D_IN ? __FW_R_SRC : __FW_R_SNK;
        return d == __FW_D_OUT ? __FW_R_SRC : __FW_R_SNK;
    endfunction

    static string par[string];      // union-find of the scope being resolved

    static function string find(string k);
        while (par[k] != k) k = par[k];
        return k;
    endfunction

    static function string jlist(string q[$]);
        string r = "[";
        q.sort();
        foreach (q[i]) r = {r, i ? ", " : "", __fw_rt_str::jstr(q[i])};
        return {r, "]"};
    endfunction

    static function string min_of(string q[$]);
        q.sort();
        return q[0];
    endfunction

    // Forms the nets of scope s and checks them; returns their JSON lines
    // keyed for sorting.
    static function void nets_of(__fw_rt_obj s, ref string out[string]);
        __fw_rt_obj   ep[string];
        string        tie_of[string];
        string        roots[$];
        par.delete();
        foreach (conns[i]) begin
            __fw_rt_conn c = conns[i];
            if (c.scope != s) continue;
            if (!par.exists(c.a.path)) begin par[c.a.path] = c.a.path; ep[c.a.path] = c.a; end
            if (c.b == null) begin
                if (tie_of.exists(c.a.path))
                    diag("FW-E-NET-MULTI", c.a.path, "tied twice");
                tie_of[c.a.path] = c.tie;
                continue;
            end
            if (!par.exists(c.b.path)) begin par[c.b.path] = c.b.path; ep[c.b.path] = c.b; end
            begin
                string ra = find(c.a.path), rb = find(c.b.path);
                if (ra != rb) par[rb] = ra;
            end
        end
        foreach (par[k]) begin
            string r = find(k);
            bit dup = 0;
            foreach (roots[i]) if (roots[i] == r) dup = 1;
            if (!dup) roots.push_back(r);
        end
        foreach (roots[ri]) begin
            string srcs[$], snks[$], sigs[$], ios[$], tied[$], all[$];
            string tv = "";
            string drv[$];
            string line;
            foreach (par[k]) begin
                int rl;
                if (find(k) != roots[ri]) continue;
                all.push_back(k);
                rl = role(s, ep[k]);
                case (rl)
                    __FW_R_SRC:   srcs.push_back(k);
                    __FW_R_SNK:   snks.push_back(k);
                    __FW_R_INOUT: ios.push_back(k);
                    default:      sigs.push_back(k);
                endcase
                if (tie_of.exists(k)) tied.push_back(k);
            end
            if (tied.size()) tv = tie_of[min_of(tied)];
            drv = srcs;
            foreach (tied[i]) drv.push_back(tied[i]);
            begin
                __fw_rt_obj s_ep[$], i_ep[$];
                foreach (srcs[i]) s_ep.push_back(ep[srcs[i]]);
                foreach (srcs[i]) i_ep.push_back(ep[srcs[i]]);
                foreach (snks[i]) i_ep.push_back(ep[snks[i]]);
                foreach (ios[i]) i_ep.push_back(ep[ios[i]]);
                __fw_rt_dom::check_net(s, s_ep, i_ep);
            end
            if (srcs.size() + tied.size() > 1)
                diag("FW-E-NET-MULTI", min_of(drv), "more than one source");
            else if (snks.size() > 0 && srcs.size() + tied.size() == 0 && ios.size() == 0)
                diag("FW-E-NET-UNDRIVEN", min_of(snks), "sinks but no source");
            line = {"{\"scope\": ", __fw_rt_str::jstr(s.path),
                    ", \"source\": ", srcs.size() ? __fw_rt_str::jstr(min_of(srcs)) : "null",
                    ", \"tie\": ", tied.size() ? __fw_rt_str::jstr(tv) : "null",
                    ", \"sinks\": ", jlist(snks),
                    ", \"signals\": ", jlist(sigs),
                    ", \"inouts\": ", jlist(ios), "}"};
            out[{s.path, " ", min_of(all)}] = line;
        end
        // unconnected inputs of the children
        foreach (s.children[i]) begin
            __fw_rt_obj lv[$];
            if (s.children[i].kind != __FW_K_COMPONENT) continue;
            s.children[i].leaves(lv);
            foreach (lv[j])
                if (lv[j].kind == __FW_K_PORT && lv[j].eff_dir() == __FW_D_IN && !par.exists(lv[j].path))
                    diag("FW-E-IN-OPEN", lv[j].path, "input is not connected or tied");
        end
    endfunction

    static function void walk(__fw_rt_obj o, bit is_build);
        fw_component c;
        if (o.detached || !$cast(c, o.h)) return;
        cur = o;
        if (is_build) c.build();
        else c.connect();
        for (int i = 0; i < o.children.size(); i++)
            if (o.children[i].kind == __FW_K_COMPONENT) walk(o.children[i], is_build);
    endfunction

    static function void check_flat(__fw_rt_obj c);
        __fw_rt_obj lv[$];
        __fw_rt_obj by_flat[string];
        foreach (c.children[i])
            if (c.children[i].is_signal()) lv.push_back(c.children[i]);
            else if (c.children[i].is_bundle()) c.children[i].leaves(lv);
        foreach (lv[i]) begin
            string f = __fw_rt_str::replace_char(lv[i].rel(c), ".", "_");
            if (by_flat.exists(f)) begin
                __fw_rt_obj later = by_flat[f].seq > lv[i].seq ? by_flat[f] : lv[i];
                diag("FW-E-NAME-FLAT", later.path, {"flattened name '", f, "' collides"});
            end else by_flat[f] = lv[i];
        end
    endfunction

    // Elaborates the created top and ends the simulation: $finish, or $fatal
    // when elaboration reported an error. fw_elab #(T) calls it; so can a
    // non-parameterized wrapper (see fw_elab.sv).
    static string nl_lines[string];    // the nets, kept for write_netlist()

    // With +fw_edges=<n>, runs the processes (__fw_rt_kern) after
    // elaboration and writes the netlist after the run.
    static task main(fw_component t);
        int nerr = elaborate(t);
        if ($test$plusargs("fw_edges")) begin
            if (nerr == 0) __fw_rt_kern::run();
            nerr = write_netlist();
        end
        if (nerr != 0) $fatal(1, "fw_elab: %0d error(s)", nerr);
        $display("fw_elab: ok");
        $finish;
    endtask

    // Runs the phases on the created top, and writes the netlist when
    // +fw_netlist=<path> is given. Returns the number of errors.
    static function int elaborate(fw_component t);
        string nl;
        string keys[$];
        string lines[string];
        __fw_rt_obj by_path[string];
        int fd, nerr = 0;
        if (top == null) begin
            diag("FW-E-ELAB-NEW", "", "no top component");
            return 1;
        end
        // build
        phase = __FW_P_BUILD;
        walk(top, 1);
        cur = null;
        foreach (ovs[i])
            if (!ovs[i].matched)
                diag("FW-W-PARAM-UNUSED", ovs[i].scope == null ? "" : ovs[i].scope.path,
                     {"override '", ovs[i].glob, "' matched nothing"});
        // connect
        phase = __FW_P_CONNECT;
        walk(top, 0);
        cur = null;
        // resolve
        phase = __FW_P_RESOLVE;
        foreach (objs[i]) begin
            fw_extern_if x;
            if (objs[i].kind != __FW_K_COMPONENT) continue;
            check_flat(objs[i]);
            if ($cast(x, objs[i].h)) do_extern(objs[i], x);
        end
        foreach (objs[i])
            if (objs[i].kind == __FW_K_COMPONENT) nets_of(objs[i], lines);
        __fw_rt_cfg::resolve();
        __fw_rt_api::check_cross();
        __fw_rt_dom::check();
        __fw_rt_api::check();
        __fw_rt_val::form_nets();
        __fw_rt_procs::discover();
        phase = __FW_P_DONE;
        nl_lines = lines;
        if (!$test$plusargs("fw_edges")) return write_netlist();
        foreach (diags[i]) if (diags[i].id.substr(0, 4) == "FW-E-") nerr++;
        return nerr;
    endfunction

    // Writes the netlist when +fw_netlist=<path> is given; after a run, it
    // holds the run's diagnostics too. Returns the number of errors.
    static function int write_netlist();
        string nl;
        string keys[$];
        __fw_rt_obj by_path[string];
        int fd, nerr = 0;
        foreach (diags[i]) if (diags[i].id.substr(0, 4) == "FW-E-") nerr++;
        if ($value$plusargs("fw_netlist=%s", nl)) begin
            string dk[$];
            string dseen[string];
            fd = $fopen(nl, "w");
            if (fd == 0) begin
                $display("FW-E-RT-IO: cannot write %s", nl);
                return nerr + 1;
            end
            $fwrite(fd, "{\n  \"top\": %s,\n  \"objects\": [", __fw_rt_str::jstr(top.tname));
            foreach (objs[i]) begin
                by_path[objs[i].path] = objs[i];
                keys.push_back(objs[i].path);
            end
            keys.sort();
            foreach (keys[i]) $fwrite(fd, "%s\n    %s", i ? "," : "", by_path[keys[i]].json());
            $fwrite(fd, "\n  ],\n  \"nets\": [");
            keys.delete();
            foreach (nl_lines[k]) keys.push_back(k);
            keys.sort();
            foreach (keys[i]) $fwrite(fd, "%s\n    %s", i ? "," : "", nl_lines[keys[i]]);
            $fwrite(fd, "\n  ],\n  \"diagnostics\": [");
            foreach (diags[i]) begin
                string k = {diags[i].path, " ", diags[i].id};
                if (dseen.exists(k)) continue;
                dseen[k] = {"{\"id\": \"", diags[i].id, "\", \"path\": ", __fw_rt_str::jstr(diags[i].path), "}"};
                dk.push_back(k);
            end
            dk.sort();
            foreach (dk[i]) $fwrite(fd, "%s\n    %s", i ? "," : "", dseen[dk[i]]);
            $fwrite(fd, "\n  ]");
            __fw_rt_proto::write(fd);
            __fw_rt_api::write(fd);
            $fwrite(fd, "\n}\n");
            $fclose(fd);
        end
        return nerr;
    endfunction

endclass
