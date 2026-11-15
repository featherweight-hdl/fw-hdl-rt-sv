// fw_rt_util.svh: rt-sv string helpers. Included inside fw_hdl_pkg.
//
// - __fw_rt_str::tn() turns a simulator $typename() into the netlist's
//   canonical type spelling (fw-hdl-spec semantics/netlist.schema.json).
// - __fw_rt_pj turns a %p rendering of a params value into JSON.
// Both are written against Verilator's $typename and %p output.

class __fw_rt_str;

    static function bit is_id_start(byte c);
        return (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || c == "_";
    endfunction

    static function bit is_digit(byte c);
        return c >= "0" && c <= "9";
    endfunction

    static function bit is_id_char(byte c);
        return is_id_start(c) || is_digit(c) || c == "$";
    endfunction

    static function bit is_lit_char(byte c);
        return is_digit(c) || (c >= "a" && c <= "f") || (c >= "A" && c <= "F")
            || c == "_" || c == "x" || c == "X" || c == "z" || c == "Z" || c == "?";
    endfunction

    static function string chr(byte c);
        string s = " ";
        s[0] = c;
        return s;
    endfunction

    static function string replace_char(string s, byte from, byte to);
        string r = s;
        for (int i = 0; i < r.len(); i++)
            if (r[i] == from) r[i] = to;
        return r;
    endfunction

    // JSON string literal.
    static function string jstr(string s);
        string r = "\"";
        for (int i = 0; i < s.len(); i++) begin
            if (s[i] == "\"" || s[i] == "\\") r = {r, "\\", chr(s[i])};
            else r = {r, chr(s[i])};
        end
        return {r, "\""};
    endfunction

    // The digits of a based literal (base h, d, o or b) as unsigned decimal.
    // ok is 0 when the value has x/z bits or does not fit in 64 bits.
    static function string lit_to_dec(byte base, string digits, output bit ok);
        longint unsigned v = 0;
        int sh;
        ok = 1;
        case (base)
            "h", "H": sh = 4;
            "o", "O": sh = 3;
            "b", "B": sh = 1;
            default:  sh = 0;
        endcase
        for (int i = 0; i < digits.len(); i++) begin
            byte c = digits[i];
            int d;
            if (c == "_") continue;
            if (is_digit(c)) d = c - "0";
            else if (c >= "a" && c <= "f") d = c - "a" + 10;
            else if (c >= "A" && c <= "F") d = c - "A" + 10;
            else begin ok = 0; return ""; end
            if (sh == 0) begin
                if (v > 64'd1844674407370955161) begin ok = 0; return ""; end
                v = v * 10 + d;
            end else begin
                if ((v >> (64 - sh)) != 0) begin ok = 0; return ""; end
                v = (v << sh) | longint'(d);
            end
        end
        return $sformatf("%0d", v);
    endfunction

    // The canonical type spelling of a $typename() result:
    // - the text from the first top-level " extends " on is dropped;
    // - "class ", "struct ", "enum " and "union " keywords are dropped;
    // - package and class-scope qualifiers ("pkg::") are dropped;
    // - based literals (8'hff) become unsigned decimal (255).
    static function string tn(string raw);
        string s = raw;
        string out = "";
        int depth = 0;
        int i;
        for (i = 0; i < s.len(); i++) begin
            byte c = s[i];
            if (c == "(" || c == "{" || c == "[") depth++;
            else if (c == ")" || c == "}" || c == "]") depth--;
            else if (depth == 0 && c == " " && s.substr(i, i + 8) == " extends ") begin
                s = s.substr(0, i - 1);
                break;
            end
        end
        i = 0;
        while (i < s.len()) begin
            byte c = s[i];
            if (c == "\"") begin
                int j = i + 1;
                while (j < s.len() && s[j] != "\"") begin
                    if (s[j] == "\\") j++;
                    j++;
                end
                out = {out, s.substr(i, j)};
                i = j + 1;
            end else if (is_id_start(c)) begin
                int j = i;
                string id;
                while (j < s.len() && is_id_char(s[j])) j++;
                id = s.substr(i, j - 1);
                if (j + 1 < s.len() && s[j] == ":" && s[j+1] == ":") begin
                    i = j + 2;
                    continue;
                end
                if ((id == "class" || id == "struct" || id == "enum" || id == "union")
                        && j < s.len() && s[j] == " ") begin
                    i = j + 1;
                    continue;
                end
                out = {out, id};
                i = j;
            end else if (is_digit(c)) begin
                int j = i;
                while (j < s.len() && is_digit(s[j])) j++;
                if (j + 1 < s.len() && s[j] == "'") begin
                    int k = j + 1;
                    int m;
                    byte b;
                    bit ok;
                    string dec;
                    if (s[k] == "s" || s[k] == "S") k++;
                    b = s[k];
                    k++;
                    m = k;
                    while (m < s.len() && is_lit_char(s[m])) m++;
                    dec = lit_to_dec(b, s.substr(k, m - 1), ok);
                    out = {out, ok ? dec : s.substr(i, m - 1)};
                    i = m;
                end else begin
                    out = {out, s.substr(i, j - 1)};
                    i = j;
                end
            end else begin
                out = {out, chr(c)};
                i++;
            end
        end
        return out;
    endfunction

    // Unsigned decimal digits d as w bits, MSB first; a leading '-' gives
    // the two's complement.
    static function string dec_to_bin(string d, int w);
        bit neg = 0;
        byte q[$];
        bit b[];
        string r = "";
        if (d.len() > 0 && d[0] == "-") begin
            neg = 1;
            d = d.substr(1, d.len() - 1);
        end
        for (int i = 0; i < d.len(); i++) if (is_digit(d[i])) q.push_back(d[i] - "0");
        b = new[w];
        for (int i = 0; i < w; i++) begin       // LSB first
            int rem = 0;
            foreach (q[j]) begin
                int c = rem * 10 + q[j];
                q[j] = c / 2;
                rem = c % 2;
            end
            b[i] = rem;
        end
        if (neg) begin
            bit carry = 1;
            for (int i = 0; i < w; i++) begin
                bit v = !b[i];
                b[i] = v ^ carry;
                carry = v & carry;
            end
        end
        for (int i = w - 1; i >= 0; i--) r = {r, b[i] ? "1" : "0"};
        return r;
    endfunction

    // Bits b (MSB first) as decimal: unsigned, or two's complement if sgn.
    static function string bin_to_dec(string b, bit sgn);
        bit neg = sgn && b.len() > 0 && b[0] == "1";
        byte d[$];                              // decimal digits, LSB first
        string r = "";
        if (neg) begin                          // magnitude: invert, add 1
            bit carry = 1;
            for (int i = b.len() - 1; i >= 0; i--) begin
                bit v = (b[i] == "0");
                b[i] = (v ^ carry) ? "1" : "0";
                carry = v & carry;
            end
        end
        d.push_back(0);
        for (int i = 0; i < b.len(); i++) begin
            int carry = (b[i] == "1");
            foreach (d[j]) begin
                int c = d[j] * 2 + carry;
                d[j] = c % 10;
                carry = c / 10;
            end
            if (carry) d.push_back(carry);
        end
        for (int i = d.size() - 1; i >= 0; i--) r = {r, chr(d[i] + "0")};
        return neg ? {"-", r} : r;
    endfunction

    // The netlist spelling of a parameter value, from its %p rendering p and
    // the $typename of __fw_rt_shape #(T). An integral value, an enum label
    // and a quoted string are p as is. A packed struct (p is the whole value
    // in decimal) is split by the member layout in the shape's struct
    // literal: "'{" then each member in decimal (with its sign if signed),
    // nested structs likewise.
    static function string pval(string p, string shape);
        int s = -1;
        int total = 0;
        int pos;
        string bits;
        string out = "";
        for (int i = 0; i + 1 < shape.len(); i++)
            if (shape[i] == "'" && shape[i+1] == "{") begin s = i; break; end
        if (s < 0) return p;
        for (int pass = 0; pass < 2; pass++) begin
            int depth = 0;
            int i = s;
            pos = 0;
            while (i < shape.len()) begin
                byte c = shape[i];
                if (c == "'" && i + 1 < shape.len() && shape[i+1] == "{") begin
                    if (pass) out = {out, "'{"};
                    depth++;
                    i += 2;
                end else if (c == "}") begin
                    if (pass) out = {out, "}"};
                    depth--;
                    i++;
                    if (depth == 0) break;
                end else if (c == ",") begin
                    if (pass) out = {out, ","};
                    i++;
                end else if (is_digit(c)) begin
                    int w = 0;
                    bit sgn = 0;
                    while (i < shape.len() && is_digit(shape[i])) begin
                        w = w * 10 + (shape[i] - "0");
                        i++;
                    end
                    if (i >= shape.len() || shape[i] != "'") return p;   // unsized
                    i++;
                    if (shape[i] == "s" || shape[i] == "S") begin sgn = 1; i++; end
                    i++;                                                  // base
                    while (i < shape.len() && is_lit_char(shape[i])) i++;
                    if (pass) out = {out, bin_to_dec(bits.substr(pos, pos + w - 1), sgn)};
                    pos += w;
                end else begin
                    i++;
                end
            end
            if (!pass) begin
                total = pos;
                if (total == 0) return p;
                for (int k = 0; k < p.len(); k++)
                    if (!(is_digit(p[k]) || (k == 0 && p[k] == "-"))) return p;  // x/z
                bits = dec_to_bin(p, total);
            end
        end
        return out;
    endfunction

endclass

// A field of a params value: its name and its JSON value.
class __fw_rt_field;
    string name;
    string json;
endclass

// Parses Verilator's %p rendering of a params value into JSON. Class handles
// are looked up in ctors: a constructor factory is written as the canonical
// type of the realization it creates.
class __fw_rt_pj;
    string s;
    int    pos;
    string ctors[string];

    function void ws();
        while (pos < s.len() && s[pos] == " ") pos++;
    endfunction

    // The top-level fields of a struct value.
    function void fields(string text, ref __fw_rt_field out[$]);
        s = text;
        pos = 0;
        out.delete();
        ws();
        if (s.substr(pos, pos + 1) != "'{") return;
        pos += 2;
        forever begin
            __fw_rt_field f;
            ws();
            if (pos >= s.len() || s[pos] == "}") break;
            f = new;
            f.name = ident_colon();
            f.json = value();
            out.push_back(f);
            ws();
            if (pos < s.len() && s[pos] == ",") pos++;
        end
    endfunction

    // "name:" at pos: returns name and moves past the colon; otherwise "".
    function string ident_colon();
        int j = pos;
        if (j >= s.len() || !__fw_rt_str::is_id_start(s[j])) return "";
        while (j < s.len() && __fw_rt_str::is_id_char(s[j])) j++;
        if (j < s.len() && s[j] == ":" && !(j + 1 < s.len() && s[j+1] == ":")) begin
            string n = s.substr(pos, j - 1);
            pos = j + 1;
            return n;
        end
        return "";
    endfunction

    function string value();
        ws();
        if (s.substr(pos, pos + 1) == "'{") begin
            string items[$];
            string names[$];
            bit named = 0;
            string r;
            pos += 2;
            forever begin
                string n;
                ws();
                if (pos >= s.len() || s[pos] == "}") break;
                n = ident_colon();
                if (n != "") named = 1;
                names.push_back(n);
                items.push_back(value());
                ws();
                if (pos < s.len() && s[pos] == ",") pos++;
            end
            pos++;
            r = named ? "{" : "[";
            foreach (items[i]) begin
                if (i) r = {r, ", "};
                if (named) r = {r, __fw_rt_str::jstr(names[i]), ": "};
                r = {r, items[i]};
            end
            return {r, named ? "}" : "]"};
        end else if (pos < s.len() && s[pos] == "\"") begin
            int j = pos + 1;
            string r;
            while (j < s.len() && s[j] != "\"") begin
                if (s[j] == "\\") j++;
                j++;
            end
            r = s.substr(pos, j);
            pos = j + 1;
            return r;
        end else begin
            int j = pos;
            string tok;
            while (j < s.len() && s[j] != "," && s[j] != "}") j++;
            tok = s.substr(pos, j - 1);
            pos = j;
            while (tok.len() > 0 && tok[tok.len()-1] == " ") tok = tok.substr(0, tok.len() - 2);
            return token(tok);
        end
    endfunction

    function string token(string tok);
        int q = -1;
        if (tok == "null") return "null";
        for (int i = 0; i < tok.len(); i++)
            if (tok[i] == "'") begin q = i; break; end
        if (q >= 0) begin
            int k = q + 1;
            byte b;
            bit ok;
            string dec;
            if (tok[k] == "s" || tok[k] == "S") k++;
            b = tok[k];
            dec = __fw_rt_str::lit_to_dec(b, tok.substr(k + 1, tok.len() - 1), ok);
            if (ok) return dec;
            return __fw_rt_str::jstr(tok.substr(q, tok.len() - 1));
        end
        if (__fw_rt_str::is_digit(tok[0]) || tok[0] == "-") return tok;
        if (ctors.exists(tok)) return __fw_rt_str::jstr(ctors[tok]);
        return __fw_rt_str::jstr(tok);
    endfunction

endclass
