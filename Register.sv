module Register #(parameter words = 64 )


   ( input logic clk,
    input  logic rst,
    input  logic [31:0] write_data,
    input  logic write_enable,
    input logic [31:0] address,
    output  logic [31:0]read_data );


 reg [31:0] mem[words-1:0] ;

always@ (posedge clk or posedge rst ) begin 
    if (rst==1)begin
        for(int i =0; i<  words;i++) begin 
            mem[i] <= 32'b0;
        end
     end 
     else if (write_enable==1)  begin 
        if (address[1:0]==2'b00)
        mem[address[7:2]]<=write_data ;
     end
end 
always_comb begin 
    read_data=mem[address[7:2]];
    
end


endmodule