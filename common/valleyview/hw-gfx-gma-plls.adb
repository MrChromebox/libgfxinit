--
-- Copyright (C) 2026 Matt DeVillier <matt.devillier@gmail.com>
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; either version 2 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--

with HW.Time;
with HW.GFX.GMA.Registers;
with HW.GFX.GMA.DPIO;

with HW.Debug;
with GNAT.Source_Info;

package body HW.GFX.GMA.PLLs
with
   Refined_State => (State => null)
is

   DPLL_VCO_ENABLE               : constant := 1 * 2 ** 31;
   DPLL_EXT_BUFFER_ENABLE_VLV    : constant := 1 * 2 ** 30;
   DPLL_REF_CLK_ENABLE_VLV       : constant := 1 * 2 ** 29;
   DPLL_VGA_MODE_DIS             : constant := 1 * 2 ** 28;
   DPLL_LOCK_VLV                 : constant := 1 * 2 ** 15;
   DPLL_INTEGRATED_CRI_CLK_VLV   : constant := 1 * 2 ** 14;
   DPLL_INTEGRATED_REF_CLK_VLV   : constant := 1 * 2 ** 13;

   type Regs_Array is array (DPLL_Pipe) of Registers.Registers_Index;

   DPLL : constant Regs_Array :=
     (Primary   => Registers.GMCH_DPLL_A,
      Secondary => Registers.GMCH_DPLL_B);

   DPLL_MD : constant Regs_Array :=
     (Primary   => Registers.GMCH_DPLL_A_MD,
      Secondary => Registers.GMCH_DPLL_B_MD);

   function Ref_Clock_Bits (Pipe : DPLL_Pipe) return Word32 is
     (DPLL_INTEGRATED_REF_CLK_VLV or
      DPLL_REF_CLK_ENABLE_VLV or
      DPLL_VGA_MODE_DIS or
      (if Pipe = Primary then 0 else DPLL_INTEGRATED_CRI_CLK_VLV));

   ----------------------------------------------------------------------------

   -- All frequencies in kHz, like in i915's dividers search.
   Ref_Clock   : constant := 100_000;
   Min_Update  : constant :=  19_200;

   subtype VCO_Range is Int64 range 4_000_000 .. 6_000_000;
   subtype Dot_Range is Int64 range    25_000 ..   270_000;

   subtype DP_Rate is DP_Bandwidth range DP_Bandwidth_1_62 .. DP_Bandwidth_2_7;
   type DP_Dividers_Array is array (DP_Rate) of DPIO.PLL_Dividers;
   DP_Dividers : constant DP_Dividers_Array :=
     (DP_Bandwidth_1_62 => (N => 5, M1 => 3, M2 => 81, P1 => 3, P2 => 2),
      DP_Bandwidth_2_7  => (N => 1, M1 => 2, M2 => 27, P1 => 2, P2 => 2));

   procedure Calculate_Dividers
     (Target   : in     Pos64;
      Dividers :    out DPIO.PLL_Dividers;
      Success  :    out Boolean)
   is
      Max_N : constant DPIO.N_Range :=
         Natural'Min (DPIO.N_Range'Last, Ref_Clock / Min_Update);

      Best_PPM : Int64 := 1_000_000;
      Best_P : Int64 := 0;

      P2 : Natural;
   begin
      Dividers := DP_Dividers (DP_Rate'First);
      Success := False;

      -- prefer smaller N, bigger P and bigger M, like i915
      for N in DPIO.N_Range'First .. Max_N loop
         for P1 in reverse DPIO.P1_Range loop
            P2 := DPIO.P2_Range'Last;
            while P2 >= DPIO.P2_Range'First loop
               for M1 in DPIO.M1_Range loop
                  declare
                     P : constant Pos64 := Pos64 (P1 * P2 * 5);
                     M2 : constant Int64 := Div_Round_Closest
                       (Target * P * Pos64 (N), Pos64 (Ref_Clock * M1));
                     VCO, Dot, PPM : Int64;
                     Better : Boolean;
                  begin
                     if M2 in Int64 (DPIO.M2_Range'First) ..
                              Int64 (DPIO.M2_Range'Last)
                     then
                        VCO := Div_Round_Closest
                          (Ref_Clock * Pos64 (M1) * M2, Pos64 (N));
                        Dot := Div_Round_Closest (VCO, P);
                        if VCO in VCO_Range and Dot in Dot_Range then
                           PPM := 1_000_000 * abs (Target - Dot) / Target;
                           if PPM < 100 and P > Best_P then
                              PPM := 0;
                              Better := True;
                           else
                              Better := PPM + 10 < Best_PPM;
                           end if;
                           if Better then
                              Dividers :=
                                (N  => N,
                                 M1 => M1,
                                 M2 => DPIO.M2_Range (M2),
                                 P1 => P1,
                                 P2 => P2);
                              Best_PPM := PPM;
                              Best_P := P;
                              Success := True;
                           end if;
                        end if;
                     end if;
                  end;
               end loop;
               P2 := P2 - (if P2 > 10 then 2 else 1);
            end loop;
         end loop;
      end loop;
   end Calculate_Dividers;

   procedure Get_Dividers
     (Port_Cfg : in     Port_Config;
      Dividers :    out DPIO.PLL_Dividers;
      Success  :    out Boolean)
   is
   begin
      if Port_Cfg.Display = DP then
         Success := Port_Cfg.DP.Bandwidth in DP_Rate;
         Dividers := DP_Dividers
           (if Success then Port_Cfg.DP.Bandwidth else DP_Rate'First);
      elsif Port_Cfg.Display in HDMI | VGA then
         Calculate_Dividers
           (Target   => Div_Round_Closest (Port_Cfg.Mode.Dotclock, 1_000),
            Dividers => Dividers,
            Success  => Success);
      else
         Dividers := DP_Dividers (DP_Rate'First);
         Success := False;
      end if;
   end Get_Dividers;

   ----------------------------------------------------------------------------

   procedure Program_DPLL
     (Pipe     : in     DPLL_Pipe;
      Dividers : in     DPIO.PLL_Dividers;
      Is_DP    : in     Boolean;
      Low_Rate : in     Boolean;
      Success  :    out Boolean)
   is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Registers.Write (DPLL (Pipe), Ref_Clock_Bits (Pipe));

      DPIO.Prepare_PLL (Pipe, Dividers, Is_DP, Low_Rate);

      Registers.Write
        (Register => DPLL (Pipe),
         Value    => Ref_Clock_Bits (Pipe) or
                     DPLL_VCO_ENABLE or DPLL_EXT_BUFFER_ENABLE_VLV);
      Registers.Posting_Read (DPLL (Pipe));
      Time.U_Delay (150);
      Registers.Wait_Set_Mask
        (Register => DPLL (Pipe),
         Mask     => DPLL_LOCK_VLV,
         TOut_MS  => 1,
         Success  => Success);

      if Success then
         Registers.Write (DPLL_MD (Pipe), 0);
         Registers.Posting_Read (DPLL_MD (Pipe));
      else
         pragma Debug (Debug.Put_Line ("DPLL failed to lock!"));
         Off (Pipe);
      end if;
   end Program_DPLL;

   procedure On
     (Pipe     : in     DPLL_Pipe;
      Port_Cfg : in     Port_Config;
      Success  :    out Boolean)
   is
      Dividers : DPIO.PLL_Dividers;
   begin
      Get_Dividers (Port_Cfg, Dividers, Success);
      if Success then
         Program_DPLL
           (Pipe     => Pipe,
            Dividers => Dividers,
            Is_DP    => Port_Cfg.Display = DP,
            Low_Rate => Port_Cfg.Display /= DP or else
                        Port_Cfg.DP.Bandwidth = DP_Bandwidth_1_62,
            Success  => Success);
      end if;
   end On;

   procedure On_RBR
     (Pipe     : in     DPLL_Pipe;
      Was_On   :    out Boolean;
      Success  :    out Boolean)
   is
   begin
      Registers.Is_Set_Mask
        (Register => DPLL (Pipe),
         Mask     => DPLL_VCO_ENABLE,
         Result   => Was_On);
      if Was_On then
         Success := True;
      else
         Program_DPLL
           (Pipe     => Pipe,
            Dividers => DP_Dividers (DP_Bandwidth_1_62),
            Is_DP    => True,
            Low_Rate => True,
            Success  => Success);
      end if;
   end On_RBR;

   procedure Off (Pipe : DPLL_Pipe) is
   begin
      Registers.Write (DPLL (Pipe), Ref_Clock_Bits (Pipe));
      Registers.Posting_Read (DPLL (Pipe));
   end Off;

   ----------------------------------------------------------------------------

   procedure Initialize is null;

   procedure Alloc
     (Port_Cfg : in     Port_Config;
      PLL      :    out T;
      Success  :    out Boolean)
   is
      Dividers : DPIO.PLL_Dividers;
   begin
      pragma Warnings
        (Off, """Dividers"" modified by call, but value might not be*",
         Reason => "Only checking that dividers can be found");
      Get_Dividers (Port_Cfg, Dividers, Success);
      pragma Warnings
        (On, """Dividers"" modified by call, but value might not be*");
      PLL := (if Success then Pipe_DPLL else Invalid);
   end Alloc;

   procedure Free (PLL : T) is null;

   procedure All_Off is
   begin
      for Pipe in DPLL_Pipe loop
         Off (Pipe);
      end loop;
   end All_Off;

   function Register_Value (PLL : T) return Word32 is (0);

end HW.GFX.GMA.PLLs;
