#
# Input monitor constraints (loaded by apf/apf_constraints.sdc)
#
# The PLL (ic|pll) makes the pixel clock (counter 0) and the same at 90
# degrees (counter 1). The monitor's values cross from clk_74a to the pixel
# clock as a snapshot that only changes in the vertical blank (im_top.sv,
# snap_win), and snap_win crosses back through three flip-flops, so the
# domains are asynchronous groups.

set pix_clks {ic|pll|altera_pll_i|*|counter[*].output_counter|divclk}

set_clock_groups -asynchronous \
 -group { bridge_spiclk } \
 -group { clk_74a } \
 -group { clk_74b } \
 -group [get_clocks $pix_clks]
