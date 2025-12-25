

import "DPI-C" context function int unsigned addFunc(int unsigned a, int unsigned b);

`uvm_analysis_imp_decl(_in_lb_ro)
`uvm_analysis_imp_decl(_out_lb_ro)

class lb_ro_sb_c extends uvm_scoreboard;
  `uvm_component_utils(lb_ro_sb_c)

  // analysis imp ports
  uvm_analysis_imp_in_lb_ro  #(lb_ro_mon_pkt_c, lb_ro_sb_c) in_lb_ro_imp_port;
  uvm_analysis_imp_out_lb_ro #(lb_ro_mon_pkt_c, lb_ro_sb_c) out_lb_ro_imp_port;

  // line queues
  lb_ro_mon_pkt_c in_line_q[$];
  lb_ro_mon_pkt_c out_line_q[$];

  int match_cnt;
  int mismatch_cnt;


  localparam int unsigned MAXRGB = (int'(1) << `RGB_WIDTH) - 1;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    in_lb_ro_imp_port  = new("in_lb_ro_imp_port",  this);
    out_lb_ro_imp_port = new("out_lb_ro_imp_port", this);
  endfunction

  // ------------------------------------------------------------
  // helpers
  // ------------------------------------------------------------
  function automatic bit [`RGB_WIDTH-1:0] clamp_rgb(input int unsigned v);
    if (v > MAXRGB) return MAXRGB[`RGB_WIDTH-1:0];
    else            return v[`RGB_WIDTH-1:0];
  endfunction

 
  function automatic rgb_t apply_offset_clamp(
      input rgb_t in_rgb,
      input bit bypass,
      input bit [`RGB_WIDTH-1:0] offset
  );
    rgb_t exp;
    int unsigned sum_r, sum_g, sum_b;

    if (bypass) begin
      exp = in_rgb;
    end
    else begin
      sum_r = addFunc(in_rgb.r, offset);
      sum_g = addFunc(in_rgb.g, offset);
      sum_b = addFunc(in_rgb.b, offset);

      exp.r = clamp_rgb(sum_r);
      exp.g = clamp_rgb(sum_g);
      exp.b = clamp_rgb(sum_b);
    end

    return exp;
  endfunction


  function automatic string rgb2s(input rgb_t p);
    return $sformatf("(%0h,%0h,%0h)", p.r, p.g, p.b);
  endfunction

  function automatic string pixq2s(input rgb_t q[$]);
    string s;
    s = "";
    foreach (q[i]) begin
      s = {s, rgb2s(q[i])};
      if (i != q.size()-1) s = {s, " "};
    end
    return s;
  endfunction

  function automatic string expq2s(input lb_ro_mon_pkt_c inL);
    string s;
    rgb_t exp;
    s = "";
    for (int unsigned i = 0; i < inL.in_pix_q.size(); i++) begin
      exp = apply_offset_clamp(inL.in_pix_q[i], inL.i_bypass, inL.i_offset_val);
      s = {s, rgb2s(exp)};
      if (i != inL.in_pix_q.size()-1) s = {s, " "};
    end
    return s;
  endfunction

  // ------------------------------------------------------------
  // run / compare
  // ------------------------------------------------------------
  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);

    in_line_q.delete();
    out_line_q.delete();
    match_cnt    = 0;
    mismatch_cnt = 0;

    fork
      compare_lines();
    join_none
  endtask

  virtual task compare_lines();
    lb_ro_mon_pkt_c inL;
    lb_ro_mon_pkt_c outL;
    int unsigned n_in, n_out;
    bit line_ok;
    rgb_t exp;

    forever begin
      wait(in_line_q.size() > 0 && out_line_q.size() > 0);

      inL  = in_line_q.pop_front();
      outL = out_line_q.pop_front();

      n_in  = inL.in_pix_q.size();
      n_out = outL.out_pix_q.size();

      if (n_in != n_out) begin
        mismatch_cnt++;
        `uvm_error(get_type_name(),
          $sformatf("Line size mismatch: in=%0d out=%0d (in_line=%0d out_line=%0d)",
                    n_in, n_out, inL.line_idx, outL.line_idx))


        `uvm_info(get_type_name(), $sformatf("  IN : %s",  pixq2s(inL.in_pix_q)),  UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("  OUT: %s",  pixq2s(outL.out_pix_q)), UVM_LOW)
        continue;
      end

      line_ok = 1;
      for (int unsigned x = 0; x < n_in; x++) begin
        exp = apply_offset_clamp(inL.in_pix_q[x], inL.i_bypass, inL.i_offset_val);

        if (outL.out_pix_q[x] !== exp) begin
          line_ok = 0;
          mismatch_cnt++;
          `uvm_error(get_type_name(),
            $sformatf("Mismatch line(in=%0d out=%0d) x=%0d | exp(R:%0h G:%0h B:%0h) act(R:%0h G:%0h B:%0h) | bypass=%0d offset=%0d",
                      inL.line_idx, outL.line_idx, x,
                      exp.r, exp.g, exp.b,
                      outL.out_pix_q[x].r, outL.out_pix_q[x].g, outL.out_pix_q[x].b,
                      inL.i_bypass, inL.i_offset_val))


          `uvm_info(get_type_name(), $sformatf("  IN : %s",  pixq2s(inL.in_pix_q)),  UVM_LOW)
          `uvm_info(get_type_name(), $sformatf("  EXP: %s",  expq2s(inL)),           UVM_LOW)
          `uvm_info(get_type_name(), $sformatf("  OUT: %s",  pixq2s(outL.out_pix_q)), UVM_LOW)
          break;
        end
      end

      if (line_ok) begin
        match_cnt++;
        `uvm_info(get_type_name(),
          $sformatf("[PASS] Line matched (in_line=%0d out_line=%0d) pix=%0d bypass=%0d offset=%0d",
                    inL.line_idx, outL.line_idx, n_in, inL.i_bypass, inL.i_offset_val),
          UVM_LOW)

      
        `uvm_info(get_type_name(), $sformatf("  IN : %s",  pixq2s(inL.in_pix_q)),   UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("  EXP: %s",  expq2s(inL)),            UVM_LOW)
        `uvm_info(get_type_name(), $sformatf("  OUT: %s",  pixq2s(outL.out_pix_q)), UVM_LOW)
      end
    end
  endtask

  
  virtual function void write_in_lb_ro(lb_ro_mon_pkt_c pkt);
    in_line_q.push_back(pkt);

    `uvm_info(get_type_name(),
      $sformatf("[IN_ENQ] line=%0d qsize=%0d pix=%0d",
                pkt.line_idx, in_line_q.size(), pkt.in_pix_cnt),
      UVM_LOW)
  endfunction

  virtual function void write_out_lb_ro(lb_ro_mon_pkt_c pkt);
    out_line_q.push_back(pkt);

    `uvm_info(get_type_name(),
      $sformatf("[OUT_ENQ] line=%0d qsize=%0d pix=%0d", 
                pkt.line_idx, out_line_q.size(), pkt.out_pix_cnt),
      UVM_LOW)
  endfunction

  // ------------------------------------------------------------
  // report
  // ------------------------------------------------------------
  virtual function void report_phase(uvm_phase phase);
    super.report_phase(phase);

    if (in_line_q.size() != 0 || out_line_q.size() != 0) begin
      `uvm_error(get_type_name(),
        $sformatf("Queues not drained: in_line_q=%0d out_line_q=%0d",
                  in_line_q.size(), out_line_q.size()))
    end

    `uvm_info(get_type_name(), "##########################", UVM_LOW)
    `uvm_info(get_type_name(), "##### COMPARE RESULT #####", UVM_LOW)
    `uvm_info(get_type_name(), "##########################", UVM_LOW)
    `uvm_info(get_type_name(), $sformatf("     MATCH COUNT = %0d    ", match_cnt), UVM_LOW)
    `uvm_info(get_type_name(), $sformatf("  MISMATCH COUNT = %0d    ", mismatch_cnt), UVM_LOW)
    `uvm_info(get_type_name(), "##########################", UVM_LOW)
  endfunction

endclass
