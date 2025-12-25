class lb_ro_monitor_c extends uvm_monitor;
  `uvm_component_utils(lb_ro_monitor_c)

  // analysis ports
  uvm_analysis_port#(lb_ro_mon_pkt_c) in_data_port;
  uvm_analysis_port#(lb_ro_mon_pkt_c) out_data_port;

  virtual interface lb_ro_if lb_ro_vif;

  // line tracking
  bit          prev_i_de, prev_o_de;
  bit          in_active, out_active;
  int unsigned in_line_idx, out_line_idx;

  lb_ro_mon_pkt_c in_pkt;
  lb_ro_mon_pkt_c out_pkt;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    in_data_port  = new("in_data_port",  this);
    out_data_port = new("out_data_port", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual lb_ro_if)::get(this, "", "lb_ro_vif", lb_ro_vif)) begin
      `uvm_fatal(get_type_name(),
        {"virtual interface must be set for: ", get_full_name(), ". lb_ro_vif"})
    end
  endfunction

  virtual task run_phase(uvm_phase phase);
    super.run_phase(phase);

    prev_i_de   = 0;
    prev_o_de   = 0;
    in_active   = 0;
    out_active  = 0;
    in_line_idx = 0;
    out_line_idx= 0;

    fork
      // IN
      forever begin
        @(posedge lb_ro_vif.i_clk iff lb_ro_vif.i_rstn);
        in_data();
        prev_i_de = lb_ro_vif.i_de;
      end

      // OUT
      forever begin
        @(posedge lb_ro_vif.i_clk iff lb_ro_vif.i_rstn);
        out_data();
        prev_o_de = lb_ro_vif.o_de;
      end
    join_none
  endtask

 
  task in_data();
    bit de = lb_ro_vif.i_de;

    // line start
    if (de && !prev_i_de && !in_active) begin
      in_active = 1;

      in_pkt = lb_ro_mon_pkt_c::type_id::create(
                $sformatf("in_line_%0d", in_line_idx), this);

      in_pkt.line_idx    = in_line_idx++;
      in_pkt.in_pix_cnt  = 0;
      in_pkt.out_pix_cnt = 0;
      in_pkt.in_pix_q.delete();
      in_pkt.out_pix_q.delete();

      // meta latch
      in_pkt.i_bypass     = lb_ro_vif.i_bypass;
      in_pkt.i_offset_val = lb_ro_vif.i_offset_val;
      in_pkt.i_hact       = lb_ro_vif.i_hact;

      in_pkt.i_vsync      = lb_ro_vif.i_vsync;
      in_pkt.i_hsync      = lb_ro_vif.i_hsync;
    end

    // pixel collect
    if (de && in_active) begin
      rgb_t p;
      p.r = lb_ro_vif.i_r_data;
      p.g = lb_ro_vif.i_g_data;
      p.b = lb_ro_vif.i_b_data;

      in_pkt.in_pix_q.push_back(p);
      in_pkt.in_pix_cnt++;
    end

    // line end
    if (!de && prev_i_de && in_active) begin
      in_active = 0;

      if (in_pkt.i_hact != 0 && in_pkt.in_pix_cnt != in_pkt.i_hact) begin
        `uvm_error(get_type_name(),
          $sformatf("IN line mismatch: got=%0d exp=%0d line=%0d",
                    in_pkt.in_pix_cnt, in_pkt.i_hact, in_pkt.line_idx))
      end

      in_data_port.write(in_pkt);
    end
  endtask

  
  task out_data();
    bit de = lb_ro_vif.o_de;

    // line start
    if (de && !prev_o_de && !out_active) begin
      out_active = 1;

      out_pkt = lb_ro_mon_pkt_c::type_id::create(
                 $sformatf("out_line_%0d", out_line_idx), this);

      out_pkt.line_idx    = out_line_idx++;
      out_pkt.in_pix_cnt  = 0;
      out_pkt.out_pix_cnt = 0;
      out_pkt.in_pix_q.delete();
      out_pkt.out_pix_q.delete();

      out_pkt.o_vsync = lb_ro_vif.o_vsync;
      out_pkt.o_hsync = lb_ro_vif.o_hsync;
    end

    // pixel collect
    if (de && out_active) begin
      rgb_t p;
      p.r = lb_ro_vif.o_r_data;
      p.g = lb_ro_vif.o_g_data;
      p.b = lb_ro_vif.o_b_data;

      out_pkt.out_pix_q.push_back(p);
      out_pkt.out_pix_cnt++;
    end

    // line end
    if (!de && prev_o_de && out_active) begin
      out_active = 0;
      out_data_port.write(out_pkt);
    end
  endtask

endclass
