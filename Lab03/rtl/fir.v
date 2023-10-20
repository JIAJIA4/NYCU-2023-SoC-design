`timescale 1ns / 1ps
module fir 
#(  parameter pADDR_WIDTH = 12,
    parameter pDATA_WIDTH = 32,
    parameter Tape_Num    = 11
)
(
	//AXI Lite
    output  reg                     awready,
    output  reg                     wready,
    input   wire                     awvalid,
    input   wire [(pADDR_WIDTH-1):0] awaddr,
    input   wire                     wvalid,
    input   wire [(pDATA_WIDTH-1):0] wdata,
	
    output  reg                     arready,
    input   wire                     rready,
    input   wire                     arvalid,
    input   wire [(pADDR_WIDTH-1):0] araddr,
    output  reg                     rvalid,
    output  reg [(pDATA_WIDTH-1):0] rdata,
	
	//AXI Stream in
    input   wire                     ss_tvalid, 
    input   wire [(pDATA_WIDTH-1):0] ss_tdata, 
    input   wire                     ss_tlast, 
    output  reg                      ss_tready, 
	
	//AXI Stream out
    input   wire                     sm_tready, 
    output  reg                     sm_tvalid, 
    output  reg [(pDATA_WIDTH-1):0] sm_tdata, 
    output  reg                     sm_tlast, 
    
    // bram for tap RAM
    output  reg [3:0]               tap_WE,
    output  reg                     tap_EN,
    output  reg [(pDATA_WIDTH-1):0] tap_Di,
    output  reg [(pADDR_WIDTH-1):0] tap_A,
    input   wire [(pDATA_WIDTH-1):0] tap_Do,

    // bram for data RAM
    output  reg [3:0]               data_WE,
    output  reg                     data_EN,
    output  reg [(pDATA_WIDTH-1):0] data_Di,
    output  reg [(pADDR_WIDTH-1):0] data_A,
    input   wire [(pDATA_WIDTH-1):0] data_Do,

    input   wire                     axis_clk,
    input   wire                     axis_rst_n
);

parameter ST_IDLE     = 'd0,
		  ST_READ_RAM = 'd1,
		  ST_READ0    = 'd2,
		  ST_READ1    = 'd3;
		  
parameter ST_WRITE0    = 'd1,
		  ST_WRITE1    = 'd2,
		  ST_WRITE_RAM = 'd3;
		  
parameter ST_STREAMIN  = 'd1,
		  ST_RAM       = 'd2,
		  ST_CAL       = 'd3,
		  ST_STREAMOUT = 'd4,
		  ST_DONE	   = 'd5;
		  


reg [1:0]cs_axir, ns_axir;
reg [1:0]cs_axiw, ns_axiw;

reg [(pADDR_WIDTH-1):0] addr_read;
reg [(pADDR_WIDTH-1):0] addr_write;

reg [(pDATA_WIDTH-1):0] data_read;
reg [(pDATA_WIDTH-1):0] data_write;

reg [31:0] ap;
reg [31:0] data_length;


reg flag_ram_write_done;
reg flag_ram_read_done;
reg flag_ss_last;
reg flag_sm_last;

reg [2:0]cs, ns;

reg signed [31:0] data_x;
reg signed [31:0] data_y;

reg signed [31:0] coef;

reg [11:0]index_tap;
reg [11:0]index_data;
reg [11:0]index_tail_data;

reg [2:0]cnt_ram;
reg [4:0]cnt_cal;
reg [4:0]cnt_round;

//AXI Stream out
always@(*)begin
	sm_tdata  = 0;
	sm_tlast  = 0;
	sm_tvalid = 0;
	
	case(cs)
	ST_STREAMOUT:begin
		sm_tdata  = data_y;
		sm_tvalid = 1;
		if(flag_ss_last)begin
			sm_tlast = 1;
		end
		else begin
			sm_tlast = 0;
		end
	end
	endcase
end

always@(posedge axis_clk)begin
	if(!axis_rst_n)begin
		data_y <= 0;
	end
	else begin
		case(cs)
		ST_RAM:begin
			data_y <= 0;
		end
		ST_CAL:begin
			data_y <= data_x * coef + data_y;
		end
		endcase
	end
end


//data ram
//ST_RAM:
//cnt_ram = 0 -> write data into ram
//cnt_ram = 1 -> read data from ram
//ST_CAL:
//read data from ram by address shift


always@(*)begin
	data_WE = 4'b0;
	data_EN = 1'b1;
	data_Di = 32'b0;
	data_A  = 32'b0;
	case(cs)
	ST_RAM:begin
		if(cnt_ram == 'd0)begin
			data_WE = 4'b1111;
			data_Di = data_x;
		end
		else begin
			data_WE = 4'b0;
			data_Di = 0;
		end
		data_A = index_data;
	end
	ST_CAL:begin
		data_A = index_data;
	end
	endcase
end

always@(posedge axis_clk)begin
	if(!axis_rst_n)begin
		index_tail_data <= 12'b0;
	end
	else begin
		case(cs)
		ST_RAM:begin
			if(cnt_ram == 'd0)begin
				if(index_tail_data == 'h28)begin
					index_tail_data <= 0;
				end
				else begin
					index_tail_data <= index_tail_data + 4;
				end
			end
		end
		ST_DONE:begin
			index_tail_data <= 12'b0;
		end
		endcase
	end
end

always@(posedge axis_clk)begin
	if(!axis_rst_n)begin
		index_data <= 12'b0;
	end
	else begin
		case(cs)
		ST_RAM:begin
			if(index_data == 0)begin
				index_data <= 'h28;
			end
			else begin
				index_data <= index_data - 4;
			end
		end
		ST_CAL:begin
			if(index_data == 0)begin
				index_data <= 'h28;
			end
			else begin
				index_data <= index_data - 4;
			end
		end
		ST_STREAMOUT:begin
			index_data <= index_tail_data;
		end
		ST_DONE:begin
			index_data <= 12'b0;
		end
		endcase
	end
end

always@(posedge axis_clk)begin
	if(!axis_rst_n)begin
		cnt_round <= 'hff;
	end
	else begin
		case(cs)
		ST_RAM:begin
			if(cnt_ram == 'd1 && cnt_round != 'd10)begin
				cnt_round <= cnt_round +1;
			end
		end
		ST_DONE:begin
			cnt_round <= 0;
		end
		endcase
	end
end

always@(posedge axis_clk)begin
	if(!axis_rst_n)begin
		cnt_cal <= 0;
	end
	else begin
		case(cs)
		ST_CAL:begin
			cnt_cal <= cnt_cal + 1;
		end
		default:begin
			cnt_cal <= 0;
		end
		endcase
	end
end

always@(posedge axis_clk)begin
	if(!axis_rst_n) cs <= ST_IDLE;
	else 			cs <= ns;
end

always@(*)begin
	case(cs)
	ST_IDLE:begin
		if(ap[0]) ns = ST_STREAMIN;
		else 	  ns = ST_IDLE;
	end
	ST_STREAMIN:begin
		if(ss_tvalid) ns = ST_RAM;
		else 		  ns = ST_STREAMIN;
	end
	ST_RAM:begin
		if(cnt_ram == 'd1) ns = ST_CAL;
		else               ns = ST_RAM;
	end
	ST_CAL:begin
		if(cnt_cal ==  cnt_round) ns = ST_STREAMOUT;
		else 					  ns = ST_CAL;
	end
	ST_STREAMOUT:begin
		if(sm_tready && flag_ss_last) ns = ST_DONE;
		else if(sm_tready) 			  ns = ST_STREAMIN;
		else		  				  ns = ST_STREAMOUT;
	end
	ST_DONE:begin
		if(rvalid && rready) ns = ST_IDLE;
		else 				 ns = ST_DONE;
	end
	default:begin
		ns  = ST_IDLE;
	end
	endcase
end

//AXI Stream in
always@(posedge axis_clk)begin
	if(!axis_rst_n)begin
		data_x <= 0;
	end
	else begin
		case(cs)
		ST_STREAMIN:begin
			if(ss_tvalid)begin
				data_x <= ss_tdata;
			end
		end
		ST_CAL:begin
			data_x <= data_Do;
		end
		endcase
	end
end

always@(*)begin
	ss_tready = 0;
	case(cs)
	ST_STREAMIN:begin
		if(ss_tvalid)begin
			ss_tready = 1;
		end
	end
	endcase
end

always@(posedge axis_clk)begin
	if(!axis_rst_n)begin
		flag_ss_last <= 0;
	end
	else begin
		case(cs)
		ST_IDLE:begin
			flag_ss_last <= 0;
		end
		ST_STREAMIN:begin
			if(ss_tlast)begin
				flag_ss_last <= 1;
			end
		end
		endcase
	end
end

always@(posedge axis_clk)begin
	if(!axis_rst_n)begin
		cnt_ram <= 0;
	end
	else begin
		case(cs)
		ST_RAM:begin
			cnt_ram <= cnt_ram +1;
		end
		default:begin
			cnt_ram <= 0;
		end
		endcase
	end
end



//AXI Lite READ   //Write data to TB
always@(posedge axis_clk)begin
	if(!axis_rst_n) begin
		addr_read <= 0;
	end
	else begin 
		case(cs_axir)
		ST_IDLE:begin
			if(arvalid) addr_read <= araddr;
		end
		endcase
	end
end

always@(*)begin
	arready = 0;
	rvalid  = 0;
	rdata   = 0;
	case(cs_axir)
	ST_IDLE:begin
		arready = 0;
		rvalid  = 0;
		rdata   = 0;
	end
	ST_READ0:begin
		arready = 1;
	end
	ST_READ1:begin
		rvalid = 1;
		rdata = data_read;
	end
	default:begin
		arready = 0;
		rvalid  = 0;
		rdata   = 0;
	end
	endcase
end

always@(posedge axis_clk)begin
	if(!axis_rst_n) cs_axir <= ST_IDLE;
	else 			cs_axir <= ns_axir;
end

always@(*)begin
	case(cs_axir)
	ST_IDLE:begin
		if(arvalid) ns_axir = ST_READ_RAM;
		else 		ns_axir = ST_IDLE;
	end
	ST_READ_RAM:begin
		if(flag_ram_read_done) ns_axir = ST_READ0;
		else 			       ns_axir = ST_READ_RAM;
	end
	ST_READ0:begin
		if(rready) ns_axir = ST_READ1;
		else 	   ns_axir = ST_READ0;
	end
	ST_READ1:begin
		ns_axir = ST_IDLE;
	end
	default:begin
		ns_axir  = ST_IDLE;
	end
	endcase
end


//AXI Lite WRITE   //Read data from TB
always@(posedge axis_clk)begin
	if(!axis_rst_n) begin
		addr_write <= 0;
	end
	else begin 
		case(cs_axiw)
		ST_IDLE:begin
			if(awvalid) addr_write <= awaddr;
		end
		endcase
	end
end
always@(posedge axis_clk)begin
	if(!axis_rst_n)begin
		data_write <= 0;
	end
	else begin
		if(wvalid && wready)begin
			data_write <= wdata;
		end
	end
end

always@(*)begin
	awready = 0;
	wready  = 0;
	case(cs_axiw)
	ST_IDLE:begin
		awready = 0;
		wready  = 0;
	end
	ST_WRITE0:begin
		awready = 1;
	end
	ST_WRITE1:begin
		wready  = 1;
	end
	default:begin
		awready = 0;
		wready  = 0;
	end
	endcase
end

always@(posedge axis_clk)begin
	if(!axis_rst_n) cs_axiw <= ST_IDLE;
	else 			cs_axiw <= ns_axiw;
end

always@(*)begin
	case(cs_axiw)
	ST_IDLE:begin
		if(awvalid) ns_axiw = ST_WRITE0; 
		else 		ns_axiw = ST_IDLE;
	end
	ST_WRITE0:begin
		ns_axiw = ST_WRITE1;
	end
	ST_WRITE1:begin
		if(wvalid) ns_axiw = ST_WRITE_RAM;
		else 	   ns_axiw = ST_WRITE1;
	end
	ST_WRITE_RAM:begin
		if(flag_ram_write_done) ns_axiw = ST_IDLE;
		else 			        ns_axiw = ST_WRITE_RAM;
	end
	default:begin
		ns_axiw  = ST_IDLE;
	end
	endcase
end

//data_read & data_write
//tap coef
always@(posedge axis_clk)begin
	if(!axis_rst_n)begin
		flag_ram_read_done  <= 0;
		flag_ram_write_done <= 0;
		data_length <= 0;
		data_read <= 0;
	end
	else begin
		if(cs_axiw == ST_WRITE_RAM) begin
			if(addr_write <= 'h14 && addr_write >= 'h10)begin
				data_length <= data_write;
			end
			flag_ram_write_done <= flag_ram_write_done + 1;
		end
		else if(cs_axir == ST_READ_RAM) begin
			if(addr_read == 'd0)begin
				if(flag_ram_read_done) begin
					data_read <= ap;
				end
			end
			else if(addr_read <= 'h14 && addr_read >= 'h10)begin
				data_read <= data_length;
			end
			else if(addr_read <= 'hff && addr_read >= 'h20) begin
				data_read <= tap_Do;
			end
			flag_ram_read_done <= flag_ram_read_done + 1;
		end
	end
end

always@(posedge axis_clk)begin
	if(!axis_rst_n)begin
		ap <= {{29{1'b0}},1'b1,1'b0,1'b0};
	end
	else begin
		if(cs == ST_STREAMIN)begin
			ap[0] = 0;
		end
		else if(cs == ST_STREAMOUT)begin
			if(flag_ss_last)begin
				ap[1] = 1;
			end
		end
		else if(cs_axiw == ST_WRITE_RAM) begin
			if(addr_write == 'd0)begin
				ap <= data_write;
			end
		end
		else if(cs_axir == ST_READ_RAM) begin
			if(addr_read == 'd0)begin
				if(flag_ram_read_done) begin
					ap[1] <= 1'b0;
				end
			end
		end
	end
end

always@(*)begin
	tap_WE = 4'b0;
	tap_EN = 1'b1;
	tap_Di = 32'b0;
	tap_A  = 32'b0;
	case(cs)
	ST_IDLE:begin
		if(cs_axiw == ST_WRITE_RAM) begin
			if(addr_write <= 'hff && addr_write >= 'h20) begin
				if(flag_ram_read_done == 'd0)begin
					tap_WE = 4'b1111;
				end
				else begin
					tap_WE = 4'b0000;
				end
				tap_Di = data_write;
				tap_A  = addr_write - 'h20;
			end
		end
		else if(cs_axir == ST_READ_RAM) begin
			if(addr_read <= 'hff && addr_read >= 'h20) begin
				tap_WE = 4'b0;
				tap_EN = 1'b1;
				tap_Di = 32'b0;
				tap_A  = addr_read - 'h20;
			end
		end
	end
	ST_RAM:begin
		tap_A = index_tap;
	end
	ST_CAL:begin
		tap_A = index_tap;
	end
	endcase
end

always@(posedge axis_clk)begin
	if(!axis_rst_n)begin
		coef <= 0;
	end
	else begin
		case(cs)
		ST_RAM:begin
			coef <= tap_Do;
		end
		ST_CAL:begin
			coef <= tap_Do;
		end
		endcase
	end
end

always@(posedge axis_clk)begin
	if(!axis_rst_n)begin
		index_tap <= 12'b0;
	end
	else begin
		case(cs)
		ST_RAM:begin
			index_tap <= index_tap + 4;
		end
		ST_CAL:begin
			index_tap <= index_tap + 4;
		end
		ST_STREAMOUT:begin
			index_tap <= 0;
		end
		endcase
	end
end

endmodule