// ============================================================================
//  SWBLI : immersed DIAMOND generator (Euler) + FREESTREAM top (no unstart) +
//  inlet slip strip.  FULLY STRUCTURED all-quad H-grid (12 transfinite blocks):
//     tiers  : BL band (wall->offset, y+ clustered) | lower-outer | upper-outer
//     strips : [0..LE] before | [LE..mid] front | [mid..TE] rear | [TE..L3] after
//  the diamond is the gap between the lower & upper tiers in the two mid strips.
//  Markers: Inlet_1, Freestream, Outlet, Wall_slip(Euler), Wall(no-slip), Diamond(Euler)
//
//  >>> MODIFIED from g_wedge: "reasonably long" diamond per advisor's request <<<
//  Changes relative to the original short diamond (g_wedge):
//    - L3 (domain length) is now DERIVED, not hardcoded: it's solved so the
//      downstream clearance after the wedge trailing edge exactly matches
//      the original g_wedge clearance (100.8 mm). This means the domain
//      grows automatically in lockstep with however long you make the
//      wedge -- tune iTE, and L3 follows -- instead of me guessing a
//      domain length independently of the wedge size.
//    - Wedge length increased: iLE/imid/iTE = 17/24/31 (was 17/23/29),
//      widening the span from 12 to 14 wall-node steps (~26% longer) --
//      enough to push secondary shocks further from the region of
//      interest, but a smaller step than the first (300mm) attempt.
//    - theta_w (shock strength) and islip (slip-wall extent) left unchanged.
// ============================================================================
SetFactory("Built-in");

// ------------------------- EDITABLE GEOMETRY -------------------------------
L1 = 80.0;                               // domain height (left)            [mm]
clear_mm = 240.0;                        // TARGET downstream clearance after wedge TE
                                          // (was 100.8 = original g_wedge clearance;
                                          // increased ~1.8x to push the exit further
                                          // downstream of the wedge/secondary shocks)
                                          // L3 is DERIVED below from this + iTE, not hardcoded.
islip = 8;                               // wall-node index: slip -> no-slip junction
// diamond given by wall-node indices so strip cuts land on wall nodes (no interp)
iLE = 17;  imid = 21;  iTE = 25;         // wedge span kept at ORIGINAL g_wedge indices.
                                          // (Do NOT lengthen this span again without also
                                          // re-deriving theta_w below -- see td_target note.)
yd  = 60.0;                              // diamond centre height           [mm]
td_target = 3.0;                         // TARGET diamond half-thickness   [mm]
                                          // (= the original g_wedge's actual half-thickness
                                          // at L3=240. theta_w is now DERIVED below so the
                                          // diamond's physical THICKNESS stays fixed no matter
                                          // how long L3/clear_mm get -- this is what was
                                          // blowing up and blocking the channel before: with a
                                          // hardcoded theta_w, thickness = front_leg*tan(theta_w)
                                          // grows every time L3 grows, since front_leg = xw_n
                                          // fraction * L3. Deriving theta_w instead keeps the
                                          // diamond thin regardless of domain length.

// ------------------------- MESH REFINEMENT ---------------------------------
mesh_refine = 2.0;   // uniform in ALL directions & regions EXCEPT wall-normal
                     // inside the BL band (that is pinned by the y+ first cell).

// ---- streamwise cell counts (SCALE with mesh_refine) ----------------------
//     >>> hardcode-tune the per-region length resolution here <<<
s1_base = 60;    //  BEFORE wedge   [0    -> x_LE]
s2_base = 28;    //  wedge FRONT (was 24, small bump for the slightly longer leg)
s3_base = 28;    //  wedge REAR  (was 24, small bump)
s4_base = 259;   //  AFTER wedge (scaled proportionally with the ~1.8x longer clear_mm)
// ---- wall-normal cell counts in the OUTER tiers (SCALE with mesh_refine) --
nLow_base = 50;  //  offset  -> dividing line (lower-outer tier)
nUp_base  = 22;  //  dividing-> freestream    (upper-outer tier)

// ------------------------- BOUNDARY LAYER (y+ pinned) ----------------------
delta_bl = 6.0;   // BL band thickness (offset distance)                    [mm]
bl_ratio = 1.15;  // wall-normal growth ratio in the BL band
// freestream state (SI) -> first-cell height from a turbulent flat-plate est.
rho_inf = 0.18985;  U_inf = 486.1;  mu_inf = 1.846e-5;   // M=1.4, 300K, 16349 Pa
L_ref   = 0.10;     // reference length for Cf  [m]
yplus   = 1.0;      // target y+ on the lower (no-slip) wall
dy1_override = 0.0; // >0 : force first-cell height [mm], ignoring the y+ estimate

// ------------------------- WALL COORDINATES --------------------------------
xw_n[] = {0.00,0.02,0.04,0.06,0.08,0.10,0.12,0.14,0.16,0.18,0.20,0.22,0.24,0.26,0.28,0.30,
0.32,0.34,0.36,0.38,0.40,0.42,0.44,0.46,0.48,0.50,0.52,0.54,0.56,0.58,0.60,0.62,0.64,0.66,0.68,
0.70,0.72,0.74,0.76,0.78,0.80,0.82,0.84,0.86,0.88,0.90,0.92,0.94,0.96,0.98,1.00};
yw[] = {0.0000,0.0000,0.0000,0.0000,0.0000,0.0000,0.0000,0.0000,0.0000,0.0000,0.0000,0.0000,
0.0000,0.0000,0.0000,0.0000,-0.0022,-0.0171,-0.0552,-0.1249,-0.2326,-0.3831,-0.5792,-0.8222,
-1.1119,-1.4470,-1.8249,-2.2418,-2.6934,-3.1744,-3.6788,-4.2004,-4.7323,-5.2677,-5.7996,-6.3212,
-6.8256,-7.3066,-7.7582,-8.1751,-8.5530,-8.8881,-9.1778,-9.4208,-9.6169,-9.7674,-9.8751,-9.9448,
-9.9829,-9.9978,-10.0000};

// ===========================================================================
//  ---  derived quantities  ---
// ===========================================================================
nW = # xw_n[];  iLast = nW - 1;  topY = yw[0] + L1;

// L3 DERIVED from the wedge: solve for the domain length that gives exactly
// clear_mm of downstream clearance after the wedge trailing edge (iTE), so
// the domain automatically grows/shrinks together with the wedge instead of
// being picked independently.
//   xTE = xw_n[iTE]*L3   and   clear_mm = L3 - xTE = L3*(1 - xw_n[iTE])
//   =>  L3 = clear_mm / (1 - xw_n[iTE])
L3 = clear_mm / (1.0 - xw_n[iTE]);

// first-cell height from y+ (turbulent flat-plate), or manual override
Re_L = rho_inf*U_inf*L_ref/mu_inf;
Cf   = 0.026 * Exp((-1.0/7.0)*Log(Re_L));
utau = U_inf*Sqrt(Cf/2.0);
dy1  = 1000.0 * yplus*mu_inf/(rho_inf*utau);      // mm
If (dy1_override > 0) dy1 = dy1_override; EndIf
// BL layer count to span delta_bl from dy1 at growth bl_ratio (y+ pinned, NOT scaled)
N_bl = Ceil( Log(1.0 + delta_bl*(bl_ratio-1.0)/dy1) / Log(bl_ratio) );
dy1_actual = delta_bl*(bl_ratio-1.0)/(Exp(N_bl*Log(bl_ratio))-1.0);

// streamwise / outer-normal counts (scaled by mesh_refine)
s1 = Floor(s1_base*mesh_refine+0.5);  If(s1<2) s1=2; EndIf
s2 = Floor(s2_base*mesh_refine+0.5);  If(s2<1) s2=1; EndIf
s3 = Floor(s3_base*mesh_refine+0.5);  If(s3<1) s3=1; EndIf
s4 = Floor(s4_base*mesh_refine+0.5);  If(s4<2) s4=2; EndIf
nLow = Floor(nLow_base*mesh_refine+0.5); If(nLow<2) nLow=2; EndIf
nUp  = Floor(nUp_base *mesh_refine+0.5); If(nUp <2) nUp =2; EndIf

xLE = xw_n[iLE]*L3;  xMD = xw_n[imid]*L3;  xTE = xw_n[iTE]*L3;
xSlip = xw_n[islip]*L3;
sSlip = Floor(s1*xSlip/xLE + 0.5);  If(sSlip<1) sSlip=1; EndIf

// theta_w DERIVED from td_target: keeps diamond thickness fixed no matter how
// long L3/clear_mm get (front_leg scales with L3, so theta_w must shrink to
// compensate -- this is what fixes the blockage seen with hardcoded theta_w).
front_leg = xMD - xLE;
theta_w = Atan(td_target / front_leg) * 180.0/Pi;
td = front_leg*Tan(theta_w*Pi/180.0);   // diamond half-thickness (== td_target, by construction)

// ---- wall + offset points -------------------------------------------------
For i In {0:iLast}
  p=newp; Point(p)={xw_n[i]*L3, yw[i], 0};  wall[]+=p;
EndFor
For i In {0:iLast}
  xi=xw_n[i]*L3; yi=yw[i];
  If (i==0)          tx=(xw_n[1]-xw_n[0])*L3;              ty=yw[1]-yw[0];
  ElseIf (i==iLast)  tx=(xw_n[iLast]-xw_n[iLast-1])*L3;    ty=yw[iLast]-yw[iLast-1];
  Else               tx=(xw_n[i+1]-xw_n[i-1])*L3;          ty=yw[i+1]-yw[i-1];
  EndIf
  tm=Sqrt(tx*tx+ty*ty); nx=-ty/tm; ny=tx/tm;
  If (i==0 || i==iLast)  ox=xi;              oy=yi+delta_bl;
  Else                   ox=xi+delta_bl*nx;  oy=yi+delta_bl*ny;
  EndIf
  p=newp; Point(p)={ox,oy,0}; off[]+=p;
EndFor

// ---- dividing / freestream / diamond points -------------------------------
D0 =newp; Point(D0) ={0,   yd,    0};      TL =newp; Point(TL) ={0,   topY, 0};
LE =newp; Point(LE) ={xLE, yd,    0};      FLE=newp; Point(FLE)={xLE, topY, 0};
DBO=newp; Point(DBO)={xMD, yd-td, 0};      FMD=newp; Point(FMD)={xMD, topY, 0};
DTO=newp; Point(DTO)={xMD, yd+td, 0};
TE =newp; Point(TE) ={xTE, yd,    0};      FTE=newp; Point(FTE)={xTE, topY, 0};
DL =newp; Point(DL) ={L3,  yd,    0};      TR =newp; Point(TR) ={L3,  topY, 0};

// ---- horizontal curves (left -> right) ------------------------------------
wsl[]={};
For i In {0:islip}
  wsl[]+=wall[i];
EndFor
w1[]={};
For i In {islip:iLE}
  w1[]+=wall[i];
EndFor
w2[]={};
For i In {iLE:imid}
  w2[]+=wall[i];
EndFor
w3[]={};
For i In {imid:iTE}
  w3[]+=wall[i];
EndFor
w4[]={};
For i In {iTE:iLast}
  w4[]+=wall[i];
EndFor
o1[]={};
For i In {0:iLE}
  o1[]+=off[i];
EndFor
o2[]={};
For i In {iLE:imid}
  o2[]+=off[i];
EndFor
o3[]={};
For i In {imid:iTE}
  o3[]+=off[i];
EndFor
o4[]={};
For i In {iTE:iLast}
  o4[]+=off[i];
EndFor
cWsl=newl; Spline(cWsl)=wsl[];  cW1=newl; Spline(cW1)=w1[];  cW2=newl; Spline(cW2)=w2[];
cW3=newl; Spline(cW3)=w3[];     cW4=newl; Spline(cW4)=w4[];
cO1=newl; Spline(cO1)=o1[];  cO2=newl; Spline(cO2)=o2[];  cO3=newl; Spline(cO3)=o3[];  cO4=newl; Spline(cO4)=o4[];
cDiv1=newl; Line(cDiv1)={D0,LE};   dLF=newl; Line(dLF)={LE,DBO};   dLR=newl; Line(dLR)={DBO,TE};   cDiv4=newl; Line(cDiv4)={TE,DL};
dUF=newl; Line(dUF)={LE,DTO};      dUR=newl; Line(dUR)={DTO,TE};
cF1=newl; Line(cF1)={TL,FLE};  cF2=newl; Line(cF2)={FLE,FMD};  cF3=newl; Line(cF3)={FMD,FTE};  cF4=newl; Line(cF4)={FTE,TR};

// ---- vertical curves (bottom -> top) --------------------------------------
aV0 =newl; Line(aV0) ={wall[0],   off[0]};     aVLE=newl; Line(aVLE)={wall[iLE],  off[iLE]};
aVMD=newl; Line(aVMD)={wall[imid], off[imid]}; aVTE=newl; Line(aVTE)={wall[iTE],  off[iTE]};
aVL3=newl; Line(aVL3)={wall[iLast],off[iLast]};
lV0 =newl; Line(lV0) ={off[0],   D0};   lVLE=newl; Line(lVLE)={off[iLE], LE};
lVMD=newl; Line(lVMD)={off[imid], DBO}; lVTE=newl; Line(lVTE)={off[iTE], TE};   lVL3=newl; Line(lVL3)={off[iLast], DL};
uV0 =newl; Line(uV0) ={D0, TL};   uVLE=newl; Line(uVLE)={LE, FLE};
uVMD=newl; Line(uVMD)={DTO,FMD};  uVTE=newl; Line(uVTE)={TE, FTE};   uVL3=newl; Line(uVL3)={DL, TR};

// ---- surfaces (Loop = bottom,right,-top,-left) ----------------------------
s=news; Line Loop(s)={cWsl,cW1, aVLE, -cO1, -aV0};      Plane Surface(s)={s}; A1=s;
s=news; Line Loop(s)={cW2, aVMD, -cO2, -aVLE};          Plane Surface(s)={s}; A2=s;
s=news; Line Loop(s)={cW3, aVTE, -cO3, -aVMD};          Plane Surface(s)={s}; A3=s;
s=news; Line Loop(s)={cW4, aVL3, -cO4, -aVTE};          Plane Surface(s)={s}; A4=s;
s=news; Line Loop(s)={cO1, lVLE, -cDiv1, -lV0};         Plane Surface(s)={s}; L1=s;
s=news; Line Loop(s)={cO2, lVMD, -dLF, -lVLE};          Plane Surface(s)={s}; L2=s;
s=news; Line Loop(s)={cO3, lVTE, -dLR, -lVMD};          Plane Surface(s)={s}; L3s=s;
s=news; Line Loop(s)={cO4, lVL3, -cDiv4, -lVTE};        Plane Surface(s)={s}; L4=s;
s=news; Line Loop(s)={cDiv1, uVLE, -cF1, -uV0};         Plane Surface(s)={s}; U1=s;
s=news; Line Loop(s)={dUF, uVMD, -cF2, -uVLE};          Plane Surface(s)={s}; U2=s;
s=news; Line Loop(s)={dUR, uVTE, -cF3, -uVMD};          Plane Surface(s)={s}; U3=s;
s=news; Line Loop(s)={cDiv4, uVL3, -cF4, -uVTE};        Plane Surface(s)={s}; U4=s;

// ---- transfinite distribution ---------------------------------------------
Transfinite Curve {cWsl}=sSlip+1;   Transfinite Curve {cW1}=s1-sSlip+1;
Transfinite Curve {cO1,cDiv1,cF1}=s1+1;
Transfinite Curve {cW2,cO2,dLF,dUF,cF2}=s2+1;
Transfinite Curve {cW3,cO3,dLR,dUR,cF3}=s3+1;
Transfinite Curve {cW4,cO4,cDiv4,cF4}=s4+1;
Transfinite Curve {aV0,aVLE,aVMD,aVTE,aVL3}=N_bl+1 Using Progression bl_ratio;
Transfinite Curve {lV0,lVLE,lVMD,lVTE,lVL3}=nLow+1;
Transfinite Curve {uV0,uVLE,uVMD,uVTE,uVL3}=nUp+1;

Transfinite Surface {A1}={wall[0],wall[iLE],off[iLE],off[0]};
Transfinite Surface {A2}={wall[iLE],wall[imid],off[imid],off[iLE]};
Transfinite Surface {A3}={wall[imid],wall[iTE],off[iTE],off[imid]};
Transfinite Surface {A4}={wall[iTE],wall[iLast],off[iLast],off[iTE]};
Transfinite Surface {L1}={off[0],off[iLE],LE,D0};
Transfinite Surface {L2}={off[iLE],off[imid],DBO,LE};
Transfinite Surface {L3s}={off[imid],off[iTE],TE,DBO};
Transfinite Surface {L4}={off[iTE],off[iLast],DL,TE};
Transfinite Surface {U1}={D0,LE,FLE,TL};
Transfinite Surface {U2}={LE,DTO,FMD,FLE};
Transfinite Surface {U3}={DTO,TE,FTE,FMD};
Transfinite Surface {U4}={TE,DL,TR,FTE};
Recombine Surface {A1,A2,A3,A4,L1,L2,L3s,L4,U1,U2,U3,U4};

// ---- markers --------------------------------------------------------------
Physical Curve("Inlet_1")   = {aV0, lV0, uV0};
Physical Curve("Freestream")= {cF1, cF2, cF3, cF4};
Physical Curve("Outlet")    = {aVL3, lVL3, uVL3};
Physical Curve("Wall_slip") = {cWsl};
Physical Curve("Wall")      = {cW1, cW2, cW3, cW4};
Physical Curve("Diamond")   = {dLF, dLR, dUF, dUR};
Physical Surface("Fluid")   = {A1,A2,A3,A4,L1,L2,L3s,L4,U1,U2,U3,U4};

Printf("dy1(y+=%g)=%g mm  N_bl=%g  first-cell actual=%g mm  td=%g mm", yplus, dy1, N_bl, dy1_actual, td);
