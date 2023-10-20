執行方式：
在linux 系統輸入 make，即可執行。

Lab3 說明
有3個interface，
AXI Stream in
AXI Stream out
AXI Lite
(1)TB傳輸(a) coef, (b) len訊號給design，然後讀回來check (AXI Lite)
(2)TB傳輸ap_start訊號給 design，然後check (AXI Lite) (ap_idle=0)
(3)TB傳輸Xn，給design(AXI Stream, AXI,Lite, AXI Lite)，
     同時開始FIR計算，
     只要計算完就可以傳輸Yn回去給TB( AXI Stream)，
     同時Xn也會持續的傳給design (Xn Yn是可以同時的)
(5)當design計算完FIR，傳完所有Yn，傳ap_done訊號給TB。

END

在AXI Lite中：
0x00[0]傳輸ap_start
0x00[1]傳輸ap_done
0x00[2]傳輸ap_idle
0x10-14 傳輸data-length
0x20-FF 傳輸tap parameters
