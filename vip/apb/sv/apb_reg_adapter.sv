// UVM register <-> APB bus adapter.
class apb_reg_adapter extends uvm_reg_adapter;
    `uvm_object_utils(apb_reg_adapter)
    function new(string name = "apb_reg_adapter");
        super.new(name);
        supports_byte_enable = 0;
        provides_responses   = 0;
    endfunction

    virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
        apb_item it = apb_item::type_id::create("it");
        it.write = (rw.kind == UVM_WRITE);
        it.addr  = rw.addr;
        it.data  = rw.data;
        return it;
    endfunction

    virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
        apb_item it;
        if (!$cast(it, bus_item)) begin `uvm_fatal("A2R", "bad bus item") return; end
        rw.kind   = it.write ? UVM_WRITE : UVM_READ;
        rw.addr   = it.addr;
        rw.data   = it.write ? it.data : it.rdata;
        rw.status = it.slverr ? UVM_NOT_OK : UVM_IS_OK;
    endfunction
endclass
