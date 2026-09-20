// Passive PWM monitor: samples the pins every clock and publishes per-pin
// level/edge transactions (plus periodic activity windows) on `ap`.
//
// Purely observational — it never drives, never checks. Checking is the consuming
// environment's job (e.g. a reference model fed from the RAL mirror); this class
// only guarantees that everything an outside-the-DUT checker or covergroup needs
// is visible on the analysis port.
class pwm_monitor #(parameter int unsigned NUM_PINS = 1) extends uvm_monitor;
    `uvm_component_param_utils(pwm_monitor#(NUM_PINS))

    pwm_agent_cfg #(NUM_PINS)     cfg;
    uvm_analysis_port #(pwm_item) ap;

    // per-pin bookkeeping
    protected bit          m_prev  [NUM_PINS];
    protected int unsigned m_held  [NUM_PINS];
    protected int unsigned m_edges [NUM_PINS];
    protected int unsigned m_win_cnt;
    protected bit          m_primed;      // first sample taken (m_prev is valid)

    function new(string n, uvm_component p);
        super.new(n, p);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        if (!uvm_config_db#(pwm_agent_cfg#(NUM_PINS))::get(this, "", "cfg", cfg))
            `uvm_fatal("NOCFG", "pwm_agent_cfg not set")
        if (cfg.vif == null)
            `uvm_fatal("NOVIF", "pwm_agent_cfg.vif is null")
        if (cfg.num_pins == 0 || cfg.num_pins > NUM_PINS)
            `uvm_fatal("BADCFG", $sformatf("num_pins=%0d out of range 1..%0d",
                                           cfg.num_pins, NUM_PINS))
    endfunction

    task run_phase(uvm_phase phase);
        fork
            sample_loop();
            reset_loop();
        join
    endtask

    // ---- sampling ----------------------------------------------------------
    protected task sample_loop();
        logic [NUM_PINS-1:0] cur;
        arm();
        forever begin
            @(cfg.vif.mon_cb);
            cur = cfg.vif.mon_cb.pwm;
            for (int unsigned i = 0; i < cfg.num_pins; i++) begin
                bit lvl = (cur[i] === 1'b1);
                if (!m_primed || lvl == m_prev[i]) begin
                    m_held[i]++;
                end else begin
                    m_edges[i]++;
                    if (cfg.en_edge_items) begin
                        pwm_item it = new_item(lvl ? PWM_RISE : PWM_FALL, i);
                        it.level       = lvl;
                        it.prev_level  = m_prev[i];
                        it.hold_cycles = m_held[i];
                        ap.write(it);
                    end
                    m_held[i] = 0;
                end
                m_prev[i] = lvl;
            end
            m_primed = 1;

            if (cfg.activity_window != 0) begin
                m_win_cnt++;
                if (m_win_cnt >= cfg.activity_window) begin
                    for (int unsigned i = 0; i < cfg.num_pins; i++) begin
                        pwm_item it = new_item(PWM_WINDOW, i);
                        it.level           = m_prev[i];
                        it.prev_level      = m_prev[i];
                        it.edges_in_window = m_edges[i];
                        it.window_cycles   = m_win_cnt;
                        ap.write(it);
                        m_edges[i] = 0;
                    end
                    m_win_cnt = 0;
                end
            end
        end
    endtask

    // ---- reset -------------------------------------------------------------
    // On reset assertion the observed waveform history is meaningless; re-arm and
    // tell subscribers so a reference model can resynchronise.
    protected task reset_loop();
        forever begin
            @(negedge cfg.vif.rst_n);
            for (int unsigned i = 0; i < cfg.num_pins; i++) begin
                pwm_item it = new_item(PWM_RESET, i);
                it.level = m_primed ? m_prev[i] : 1'b0;
                ap.write(it);
            end
            arm();
        end
    endtask

    protected function void arm();
        m_primed  = 0;
        m_win_cnt = 0;
        for (int unsigned i = 0; i < NUM_PINS; i++) begin
            m_prev[i]  = 1'b0;
            m_held[i]  = 0;
            m_edges[i] = 0;
        end
    endfunction

    protected function pwm_item new_item(pwm_evt_e k, int unsigned pin);
        pwm_item it = pwm_item::type_id::create("pwm_item");
        it.kind    = k;
        it.pin     = pin;
        it.t_event = $realtime;
        return it;
    endfunction
endclass
