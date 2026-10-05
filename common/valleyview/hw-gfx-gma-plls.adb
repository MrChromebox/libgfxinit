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
with HW.GFX.GMA.Config;
with HW.GFX.GMA.Registers;
with HW.GFX.GMA.DPIO;

with HW.Debug;
with GNAT.Source_Info;

package body HW.GFX.GMA.PLLs
with
   Refined_State =>
     (State => (PHY_Control, Release_CL2_Override, Release_RBR_Override))
is

   use type DPIO_CHV.Channel_Type;

   -- Copy of the write-only DISPLAY_PHY_CONTROL register of Braswell.
   PHY_Control : Word32;

   Release_CL2_Override : Boolean;
   Release_RBR_Override : Boolean;

   DPLL_VCO_ENABLE               : constant := 1 * 2 ** 31;
   DPLL_EXT_BUFFER_ENABLE_VLV    : constant := 1 * 2 ** 30;
   DPLL_REF_CLK_ENABLE_VLV       : constant := 1 * 2 ** 29;
   DPLL_VGA_MODE_DIS             : constant := 1 * 2 ** 28;
   DPLL_LOCK_VLV                 : constant := 1 * 2 ** 15;
   DPLL_INTEGRATED_CRI_CLK_VLV   : constant := 1 * 2 ** 14;
   DPLL_INTEGRATED_REF_CLK_VLV   : constant := 1 * 2 ** 13;
   DPLL_SSC_REF_CLK_CHV          : constant := 1 * 2 ** 13;

   DPLL_PORTB_READY_MASK         : constant := 16#0f#;
   DPLL_PORTC_READY_MASK         : constant := 16#f0#;
   DPLL_PORTD_READY_MASK         : constant := 16#0f#;

   type Regs_Array is array (DPLL_Pipe) of Registers.Registers_Index;

   DPLL : constant Regs_Array :=
     (Primary   => Registers.GMCH_DPLL_A,
      Secondary => Registers.GMCH_DPLL_B,
      Tertiary  => Registers.CHV_DPLL_C);

   function Ref_Clock_Bits (Pipe : DPLL_Pipe) return Word32 is
     ((if Config.Has_CHV_PHY
       then DPLL_SSC_REF_CLK_CHV
       else DPLL_INTEGRATED_REF_CLK_VLV) or
      DPLL_REF_CLK_ENABLE_VLV or
      DPLL_VGA_MODE_DIS or
      (if Pipe = Primary then 0 else DPLL_INTEGRATED_CRI_CLK_VLV));

   ----------------------------------------------------------------------------

   -- All frequencies in kHz, like in i915's dividers search.
   Ref_Clock   : constant := 100_000;
   Min_Update  : constant :=  19_200;

   subtype VCO_Range is Int64 range 4_000_000 .. 6_000_000;
   subtype Dot_Range is Int64 range    25_000 ..   270_000;

   subtype CHV_VCO_Range is Int64 range 4_800_000 .. 6_480_000;
   subtype CHV_Dot_Range is Int64 range    25_000 ..   540_000;

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

   -- The M2 divider of Braswell is a 22-bit binary fixed-point number,
   -- N is always 1, M1 always 2.
   function CHV_VCO (M2 : DPIO_CHV.M2_Range) return Int64 is
     (Div_Round_Closest (Ref_Clock * 2 * M2, 2 ** 22));

   procedure CHV_Calculate_Dividers
     (Target   : in     Pos64;
      Dividers :    out DPIO_CHV.PLL_Dividers;
      Success  :    out Boolean)
   is
      Best_P : Int64 := 0;

      P2 : Natural;
   begin
      Dividers := (P1 => 4, P2 => 2, M2 => DPIO_CHV.M2_Range'First);
      Success := False;

      -- prefer bigger P, like i915
      for P1 in reverse DPIO_CHV.P1_Range loop
         P2 := DPIO_CHV.P2_Range'Last;
         while P2 >= DPIO_CHV.P2_Range'First loop
            declare
               P : constant Pos64 := Pos64 (P1 * P2 * 5);
               M2 : constant Int64 := Div_Round_Closest
                 (Target * P * 2 ** 22, Pos64 (Ref_Clock * 2));
               VCO, Dot : Int64;
            begin
               if M2 in DPIO_CHV.M2_Range then
                  VCO := CHV_VCO (M2);
                  Dot := Div_Round_Closest (VCO, P);
                  if VCO in CHV_VCO_Range and Dot in CHV_Dot_Range and
                     P > Best_P
                  then
                     Dividers := (P1 => P1, P2 => P2, M2 => M2);
                     Best_P := P;
                     Success := True;
                  end if;
               end if;
            end;
            P2 := P2 - (if P2 > 10 then 2 else 1);
         end loop;
      end loop;
   end CHV_Calculate_Dividers;

   procedure CHV_Get_Dividers
     (Port_Cfg : in     Port_Config;
      Dividers :    out DPIO_CHV.PLL_Dividers;
      Success  :    out Boolean)
   is
   begin
      if Port_Cfg.Display = DP and then Port_Cfg.DP.Bandwidth in DP_Rate then
         CHV_Calculate_Dividers
           (Target   => DP_Symbol_Rate (Port_Cfg.DP.Bandwidth) / 1_000,
            Dividers => Dividers,
            Success  => Success);
      elsif Port_Cfg.Display = HDMI then
         CHV_Calculate_Dividers
           (Target   => Div_Round_Closest (Port_Cfg.Mode.Dotclock, 1_000),
            Dividers => Dividers,
            Success  => Success);
      else
         Dividers := (P1 => 4, P2 => 2, M2 => DPIO_CHV.M2_Range'First);
         Success := False;
      end if;
   end CHV_Get_Dividers;

   ----------------------------------------------------------------------------

   procedure Program_DPLL
     (Pipe     : in     DPIO.DPIO_Pipe;
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
         Registers.Write
           (Register => (if Pipe = Primary
                         then Registers.GMCH_DPLL_A_MD
                         else Registers.GMCH_DPLL_B_MD),
            Value    => 0);
      else
         pragma Debug (Debug.Put_Line ("DPLL failed to lock!"));
         Off (Pipe);
      end if;
   end Program_DPLL;

   procedure CHV_Program_DPLL
     (Pipe     : in     DPLL_Pipe;
      Dividers : in     DPIO_CHV.PLL_Dividers;
      Success  :    out Boolean)
   is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Registers.Write (DPLL (Pipe), Ref_Clock_Bits (Pipe));

      DPIO_CHV.Prepare_PLL (Pipe, Dividers, CHV_VCO (Dividers.M2));
      DPIO_CHV.Set_DCLKP (Pipe, True);
      Time.U_Delay (1);

      Registers.Write (DPLL (Pipe), Ref_Clock_Bits (Pipe) or DPLL_VCO_ENABLE);
      Registers.Wait_Set_Mask
        (Register => DPLL (Pipe),
         Mask     => DPLL_LOCK_VLV,
         TOut_MS  => 1,
         Success  => Success);

      if Success then
         if Pipe = Primary then
            Registers.Write (Registers.GMCH_DPLL_A_MD, 0);
         else
            -- There is no DPLL_MD for pipe C, the value of DPLL_B_MD
            -- is propagated to the selected pipe through CBR4.
            Registers.Write
              (Register => Registers.VLV_CBR4,
               Value    => Shift_Left (1, 7 + 11 * Pipe_Index'Pos (Pipe)));
            Registers.Write (Registers.GMCH_DPLL_B_MD, 0);
            Registers.Write (Registers.VLV_CBR4, 0);
         end if;
      else
         pragma Debug (Debug.Put_Line ("DPLL failed to lock!"));
         Off (Pipe);
      end if;
   end CHV_Program_DPLL;

   procedure On
     (Pipe     : in     DPLL_Pipe;
      Port_Cfg : in     Port_Config;
      Success  :    out Boolean)
   is
   begin
      if Config.Has_CHV_PHY then
         declare
            Dividers : DPIO_CHV.PLL_Dividers;
         begin
            CHV_Get_Dividers (Port_Cfg, Dividers, Success);
            if Success then
               CHV_Program_DPLL (Pipe, Dividers, Success);
            end if;
         end;
      elsif Pipe in DPIO.DPIO_Pipe then
         declare
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
         end;
      else
         Success := False;
      end if;
   end On;

   procedure Powergate_Channel
     (PHY      : in     DPIO_CHV.PHY_Type;
      CH       : in     DPIO_CHV.Channel_Type;
      Override : in     Boolean;
      Was_Override : out Boolean);

   procedure On_RBR
     (Pipe     : in     DPLL_Pipe;
      Port     : in     GPU_Port;
      Was_On   :    out Boolean;
      Success  :    out Boolean)
   is
      Was_Override : Boolean;
   begin
      Registers.Is_Set_Mask
        (Register => DPLL (Pipe),
         Mask     => DPLL_VCO_ENABLE,
         Result   => Was_On);
      if Was_On then
         Success := True;
      elsif Config.Has_CHV_PHY then
         -- The lanes have to be powered for the DPLL to work.
         if Port in DPIO_CHV.CHV_Port then
            Powergate_Channel
              (PHY          => DPIO_CHV.Port_PHY (Port),
               CH           => DPIO_CHV.Port_Channel (Port),
               Override     => True,
               Was_Override => Was_Override);
            Release_RBR_Override := not Was_Override;
         end if;
         declare
            Dividers : DPIO_CHV.PLL_Dividers;
         begin
            CHV_Calculate_Dividers
              (Target   => DP_Symbol_Rate (DP_Bandwidth_1_62) / 1_000,
               Dividers => Dividers,
               Success  => Success);
            if Success then
               CHV_Program_DPLL (Pipe, Dividers, Success);
            end if;
         end;
      elsif Pipe in DPIO.DPIO_Pipe then
         Program_DPLL
           (Pipe     => Pipe,
            Dividers => DP_Dividers (DP_Bandwidth_1_62),
            Is_DP    => True,
            Low_Rate => True,
            Success  => Success);
      else
         Success := False;
      end if;
   end On_RBR;

   procedure Off (Pipe : DPLL_Pipe)
   is
      Was_On : Boolean;
   begin
      Registers.Is_Set_Mask
        (Register => DPLL (Pipe),
         Mask     => DPLL_VCO_ENABLE,
         Result   => Was_On);

      Registers.Write (DPLL (Pipe), Ref_Clock_Bits (Pipe));
      Registers.Posting_Read (DPLL (Pipe));

      -- Only touch the PHY if the DPLL ran, it might be powered down.
      if Config.Has_CHV_PHY and Was_On then
         DPIO_CHV.Set_DCLKP (Pipe, False);
      end if;
   end Off;

   ----------------------------------------------------------------------------

   procedure Write_PHY_Control is
   begin
      Registers.Write (Registers.CHV_DISPLAY_PHY_CONTROL, PHY_Control);
   end Write_PHY_Control;

   procedure Powergate_Channel
     (PHY      : in     DPIO_CHV.PHY_Type;
      CH       : in     DPIO_CHV.Channel_Type;
      Override : in     Boolean;
      Was_Override : out Boolean)
   is
      OVRD_EN : constant Word32 :=
         DPIO_CHV.PHY_CH_POWER_DOWN_OVRD_EN (PHY, CH);
      All_Lanes : constant Word32 :=
         DPIO_CHV.PHY_CH_POWER_DOWN_OVRD (16#f#, PHY, CH);
   begin
      Was_Override := (PHY_Control and OVRD_EN) /= 0;
      if Override /= Was_Override then
         if Override then
            PHY_Control := PHY_Control or OVRD_EN;
         else
            PHY_Control := PHY_Control and not OVRD_EN;
         end if;
         Write_PHY_Control;

         if Override and (PHY_Control and All_Lanes) /= All_Lanes then
            DPIO_CHV.Wait_Common_Lane_Powered (PHY, CH);
         end if;
      end if;
   end Powergate_Channel;

   -- Lanes set in `Mask` are powered down, if `Override` is set.
   procedure Powergate_Lanes
     (PHY      : DPIO_CHV.PHY_Type;
      CH       : DPIO_CHV.Channel_Type;
      Override : Boolean;
      Mask     : Word32)
   is
      OVRD_EN : constant Word32 :=
         DPIO_CHV.PHY_CH_POWER_DOWN_OVRD_EN (PHY, CH);
   begin
      PHY_Control := PHY_Control and
         not DPIO_CHV.PHY_CH_POWER_DOWN_OVRD (16#f#, PHY, CH);
      if Override then
         PHY_Control := PHY_Control or OVRD_EN;
      else
         PHY_Control := PHY_Control and not OVRD_EN;
      end if;
      PHY_Control := PHY_Control or
         DPIO_CHV.PHY_CH_POWER_DOWN_OVRD (Mask, PHY, CH);
      Write_PHY_Control;

      if Override and (Mask and 16#f#) /= 16#f# then
         DPIO_CHV.Wait_Common_Lane_Powered (PHY, CH);
      end if;
   end Powergate_Lanes;

   procedure Off_RBR (Pipe : DPLL_Pipe; Port : GPU_Port)
   is
      Was_Override : Boolean;
   begin
      Off (Pipe);

      if Release_RBR_Override and Port in DPIO_CHV.CHV_Port then
         Powergate_Channel
           (PHY          => DPIO_CHV.Port_PHY (Port),
            CH           => DPIO_CHV.Port_Channel (Port),
            Override     => False,
            Was_Override => Was_Override);
      end if;
      Release_RBR_Override := False;
   end Off_RBR;

   ----------------------------------------------------------------------------

   procedure PHY_Control_Init (PHY0_On, PHY1_On : Boolean)
   is
      use DPIO_CHV;

      procedure Init_Channel
        (PHY      : PHY_Type;
         CH       : Channel_Type;
         Status   : Word32)
      is
         -- Lanes that are powered down are flagged in `Status`.
         Mask : constant Word32 := (if Status = 16#f# then 0 else Status);
      begin
         if Status /= 16#f# then
            PHY_Control := PHY_Control or PHY_CH_POWER_DOWN_OVRD_EN (PHY, CH);
         end if;
         PHY_Control := PHY_Control or PHY_CH_POWER_DOWN_OVRD (Mask, PHY, CH);
      end Init_Channel;

      Status : Word32;
   begin
      PHY_Control := PHY_Control_Initial;

      if PHY0_On then
         Registers.Read (Registers.GMCH_DPLL_A, Status);
         Init_Channel (PHY0, CH0, Status and DPLL_PORTB_READY_MASK);
         Init_Channel
           (PHY0, CH1, Shift_Right (Status and DPLL_PORTC_READY_MASK, 4));
         PHY_Control := PHY_Control or PHY_COM_LANE_RESET_DEASSERT (PHY0);
      end if;

      if PHY1_On then
         Registers.Read (Registers.CHV_DPIO_PHY_STATUS, Status);
         Init_Channel (PHY1, CH0, Status and DPLL_PORTD_READY_MASK);
         PHY_Control := PHY_Control or PHY_COM_LANE_RESET_DEASSERT (PHY1);
      end if;
   end PHY_Control_Init;

   procedure PHY_Common_Lane_Reset_Deassert (PHY : DPIO_CHV.PHY_Type) is
   begin
      PHY_Control := PHY_Control or DPIO_CHV.PHY_COM_LANE_RESET_DEASSERT (PHY);
      Write_PHY_Control;
   end PHY_Common_Lane_Reset_Deassert;

   procedure PHY_Common_Lane_Reset_Assert (PHY : DPIO_CHV.PHY_Type) is
   begin
      PHY_Control := PHY_Control and
         not DPIO_CHV.PHY_COM_LANE_RESET_DEASSERT (PHY);
      Write_PHY_Control;
   end PHY_Common_Lane_Reset_Assert;

   procedure PHY_Pre_PLL_Enable
     (Pipe        : DPLL_Pipe;
      Port        : DPIO_CHV.CHV_Port;
      Lane_Count  : DP_Lane_Count)
   is
      Was_Override : Boolean;
   begin
      -- The DPLL of pipe B lives in the second common lane of PHY0,
      -- which has to be powered even if port B doesn't use it.
      if DPIO_CHV.Port_Channel (Port) = DPIO_CHV.CH0 and Pipe = Secondary then
         Powergate_Channel
           (PHY          => DPIO_CHV.PHY0,
            CH           => DPIO_CHV.CH1,
            Override     => True,
            Was_Override => Was_Override);
         Release_CL2_Override := not Was_Override;
      else
         Release_CL2_Override := False;
      end if;

      Powergate_Lanes
        (PHY      => DPIO_CHV.Port_PHY (Port),
         CH       => DPIO_CHV.Port_Channel (Port),
         Override => True,
         Mask     => DPIO_CHV.Unused_Lane_Mask (Lane_Count));

      DPIO_CHV.Pre_PLL_Enable (Pipe, Port, Lane_Count);
   end PHY_Pre_PLL_Enable;

   procedure PHY_Post_Encoder_Enable
   is
      Was_Override : Boolean;
   begin
      if Release_CL2_Override then
         Powergate_Channel
           (PHY          => DPIO_CHV.PHY0,
            CH           => DPIO_CHV.CH1,
            Override     => False,
            Was_Override => Was_Override);
         Release_CL2_Override := False;
      end if;
   end PHY_Post_Encoder_Enable;

   procedure PHY_Post_PLL_Disable
     (Pipe  : DPLL_Pipe;
      Port  : DPIO_CHV.CHV_Port) is
   begin
      DPIO_CHV.Post_PLL_Disable (Pipe, Port);

      Powergate_Lanes
        (PHY      => DPIO_CHV.Port_PHY (Port),
         CH       => DPIO_CHV.Port_Channel (Port),
         Override => False,
         Mask     => 0);
   end PHY_Post_PLL_Disable;

   ----------------------------------------------------------------------------

   procedure Initialize is
   begin
      PHY_Control := DPIO_CHV.PHY_Control_Initial;
      Release_CL2_Override := False;
      Release_RBR_Override := False;
   end Initialize;

   procedure Alloc
     (Port_Cfg : in     Port_Config;
      PLL      :    out T;
      Success  :    out Boolean)
   is
   begin
      pragma Warnings
        (Off, """Dividers"" modified by call, but value might not be*",
         Reason => "Only checking that dividers can be found");
      if Config.Has_CHV_PHY then
         declare
            Dividers : DPIO_CHV.PLL_Dividers;
         begin
            CHV_Get_Dividers (Port_Cfg, Dividers, Success);
         end;
      else
         declare
            Dividers : DPIO.PLL_Dividers;
         begin
            Get_Dividers (Port_Cfg, Dividers, Success);
         end;
      end if;
      pragma Warnings
        (On, """Dividers"" modified by call, but value might not be*");
      PLL := (if Success then Pipe_DPLL else Invalid);
   end Alloc;

   procedure Free (PLL : T) is null;

   procedure All_Off is
   begin
      for Pipe in Primary .. Config.Max_Pipe loop
         Off (Pipe);
      end loop;
   end All_Off;

   function Register_Value (PLL : T) return Word32 is (0);

end HW.GFX.GMA.PLLs;
