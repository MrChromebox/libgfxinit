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

with HW.GFX.DP_Training;
with HW.GFX.GMA.DP_Aux_Ch;
with HW.GFX.GMA.DP_Info;
with HW.GFX.GMA.Registers;
with HW.GFX.GMA.DPIO;
with HW.GFX.GMA.DPIO_CHV;

with HW.Debug;
with GNAT.Source_Info;

package body HW.GFX.GMA.SoC.DP is

   type DP_Array is array (SoC_Port) of Registers.Registers_Index;
   DP_CTL : constant DP_Array :=
     (DIGI_B => Registers.GMCH_DP_B,
      DIGI_C => Registers.GMCH_DP_C,
      DIGI_D => Registers.GMCH_DP_D);

   DP_CTL_DISPLAY_PORT_ENABLE          : constant := 1 * 2 ** 31;
   DP_CTL_PORT_WIDTH_SHIFT             : constant :=          19;
   DP_CTL_ENHANCED_FRAMING_ENABLE      : constant := 1 * 2 ** 18;
   DP_CTL_LINK_TRAIN_MASK              : constant := 3 * 2 ** 28;
   DP_CTL_VSYNC_ACTIVE_HIGH            : constant := 1 * 2 **  4;
   DP_CTL_HSYNC_ACTIVE_HIGH            : constant := 1 * 2 **  3;
   DP_CTL_PORT_DETECT                  : constant := 1 * 2 **  2;

   function DP_CTL_PORT_WIDTH (Lane_Count : DP_Lane_Count) return Word32 is
     (Shift_Left (Word32 (Lane_Count_As_Integer (Lane_Count)) - 1,
                  DP_CTL_PORT_WIDTH_SHIFT));

   type DP_CTL_LINK_TRAIN_Array is array (DP_Info.Training_Pattern) of Word32;
   DP_CTL_LINK_TRAIN : constant DP_CTL_LINK_TRAIN_Array :=
     (DP_Info.TP_1      => 0 * 2 ** 28,
      DP_Info.TP_2      => 1 * 2 ** 28,
      DP_Info.TP_3      => 1 * 2 ** 28,
      DP_Info.TP_Idle   => 2 * 2 ** 28,
      DP_Info.TP_None   => 3 * 2 ** 28);

   ----------------------------------------------------------------------------

   -- i915: vlv_set_signal_levels()
   type PHY_Levels is record
      Valid          : Boolean;
      De_Emphasis    : Word32;
      Uniq_Transcale : Word32;
   end record;
   Invalid_Levels : constant PHY_Levels := (False, 0, 0);

   type PHY_Levels_Array is
      array (DP_Info.DP_Pre_Emph, DP_Info.DP_Voltage_Swing) of PHY_Levels;
   Levels : constant PHY_Levels_Array :=
     (DP_Info.Emph_Level_0 =>
        (DP_Info.VS_Level_0 => (True, 16#2b40_5555#, 16#552a_b83a#),
         DP_Info.VS_Level_1 => (True, 16#2b40_4040#, 16#5548_b83a#),
         DP_Info.VS_Level_2 => (True, 16#2b24_5555#, 16#5560_b83a#),
         DP_Info.VS_Level_3 => (True, 16#2b40_5555#, 16#5598_da3a#)),
      DP_Info.Emph_Level_1 =>
        (DP_Info.VS_Level_0 => (True, 16#2b40_4040#, 16#5552_b83a#),
         DP_Info.VS_Level_1 => (True, 16#2b40_4848#, 16#5580_b83a#),
         DP_Info.VS_Level_2 => (True, 16#2b40_4040#, 16#55ad_da3a#),
         DP_Info.VS_Level_3 => Invalid_Levels),
      DP_Info.Emph_Level_2 =>
        (DP_Info.VS_Level_0 => (True, 16#2b30_5555#, 16#5570_b83a#),
         DP_Info.VS_Level_1 => (True, 16#2b2b_4040#, 16#55ad_da3a#),
         others             => Invalid_Levels),
      DP_Info.Emph_Level_3 =>
        (DP_Info.VS_Level_0 => (True, 16#1b40_5555#, 16#55ad_da3a#),
         others             => Invalid_Levels));

   Pre_Emphasis : constant array (DP_Info.DP_Pre_Emph) of Word32 :=
     (DP_Info.Emph_Level_0 => 16#0000_4000#,
      DP_Info.Emph_Level_1 => 16#0000_2000#,
      DP_Info.Emph_Level_2 => 16#0000_0000#,
      DP_Info.Emph_Level_3 => 16#0000_6000#);

   -- i915: chv_set_signal_levels()
   type CHV_PHY_Levels is record
      Valid             : Boolean;
      Margin            : Word32;
      Uniq_Trans_Scale  : Boolean;
   end record;
   CHV_Invalid_Levels : constant CHV_PHY_Levels := (False, 0, False);

   type CHV_PHY_Levels_Array is
      array (DP_Info.DP_Pre_Emph, DP_Info.DP_Voltage_Swing) of CHV_PHY_Levels;
   CHV_Levels : constant CHV_PHY_Levels_Array :=
     (DP_Info.Emph_Level_0 =>
        (DP_Info.VS_Level_0 => (True,  52, False),
         DP_Info.VS_Level_1 => (True,  77, False),
         DP_Info.VS_Level_2 => (True, 102, False),
         DP_Info.VS_Level_3 => (True, 154, True)),
      DP_Info.Emph_Level_1 =>
        (DP_Info.VS_Level_0 => (True,  78, False),
         DP_Info.VS_Level_1 => (True, 116, False),
         DP_Info.VS_Level_2 => (True, 154, False),
         DP_Info.VS_Level_3 => CHV_Invalid_Levels),
      DP_Info.Emph_Level_2 =>
        (DP_Info.VS_Level_0 => (True, 104, False),
         DP_Info.VS_Level_1 => (True, 154, False),
         others             => CHV_Invalid_Levels),
      DP_Info.Emph_Level_3 =>
        (DP_Info.VS_Level_0 => (True, 154, False),
         others             => CHV_Invalid_Levels));

   CHV_De_Emphasis : constant array (DP_Info.DP_Pre_Emph) of Word32 :=
     (DP_Info.Emph_Level_0 => 128,
      DP_Info.Emph_Level_1 =>  85,
      DP_Info.Emph_Level_2 =>  64,
      DP_Info.Emph_Level_3 =>  43);

   ----------------------------------------------------------------------------

   pragma Warnings (GNATprove, Off, "unused variable ""Port""",
                    Reason => "Needed for a common interface");
   function Max_V_Swing
     (Port : SoC_Port)
      return DP_Info.DP_Voltage_Swing
   is
   begin
      return DP_Info.VS_Level_3;
   end Max_V_Swing;

   function Max_Pre_Emph
     (Port        : SoC_Port;
      Train_Set   : DP_Info.Train_Set)
      return DP_Info.DP_Pre_Emph
   is
   begin
      return
        (case Train_Set.Voltage_Swing is
            when DP_Info.VS_Level_0 => DP_Info.Emph_Level_3,
            when DP_Info.VS_Level_1 => DP_Info.Emph_Level_2,
            when DP_Info.VS_Level_2 => DP_Info.Emph_Level_1,
            when DP_Info.VS_Level_3 => DP_Info.Emph_Level_0);
   end Max_Pre_Emph;
   pragma Warnings (GNATprove, On, "unused variable ""Port""");

   ----------------------------------------------------------------------------

   pragma Warnings (GNATprove, Off, "unused variable ""Link""",
                    Reason => "Needed for a common interface");
   procedure Set_Training_Pattern
     (Port     : SoC_Port;
      Link     : DP_Link;
      Pattern  : DP_Info.Training_Pattern)
   is
   begin
      Registers.Unset_And_Set_Mask
        (Register    => DP_CTL (Port),
         Mask_Unset  => DP_CTL_LINK_TRAIN_MASK,
         Mask_Set    => DP_CTL_LINK_TRAIN (Pattern));
      Registers.Posting_Read (DP_CTL (Port));
   end Set_Training_Pattern;

   procedure Set_Signal_Levels
     (Port        : SoC_Port;
      Link        : DP_Link;
      Train_Set   : DP_Info.Train_Set)
   is
      PHY : PHY_Levels renames
         Levels (Train_Set.Pre_Emph, Train_Set.Voltage_Swing);
      CHV_PHY : CHV_PHY_Levels renames
         CHV_Levels (Train_Set.Pre_Emph, Train_Set.Voltage_Swing);
   begin
      if Config.Has_CHV_PHY and CHV_PHY.Valid then
         DPIO_CHV.Set_Signal_Levels
           (Port              => Port,
            Lane_Count        => Link.Lane_Count,
            De_Emphasis       => CHV_De_Emphasis (Train_Set.Pre_Emph),
            Margin            => CHV_PHY.Margin,
            Uniq_Trans_Scale  => CHV_PHY.Uniq_Trans_Scale);
      elsif not Config.Has_CHV_PHY and PHY.Valid and Port in DPIO.DPIO_Port
      then
         DPIO.Set_Signal_Levels
           (Port           => Port,
            De_Emphasis    => PHY.De_Emphasis,
            Pre_Emphasis   => Pre_Emphasis (Train_Set.Pre_Emph),
            Uniq_Transcale => PHY.Uniq_Transcale);
      else
         pragma Debug (Debug.Put_Line ("Invalid DP signal levels!"));
         null;
      end if;
   end Set_Signal_Levels;
   pragma Warnings (GNATprove, On, "unused variable ""Link""");

   procedure Off (Port : SoC_Port)
   is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Registers.Unset_And_Set_Mask
        (Register    => DP_CTL (Port),
         Mask_Unset  => DP_CTL_LINK_TRAIN_MASK,
         Mask_Set    => DP_CTL_LINK_TRAIN (DP_Info.TP_Idle));
      Registers.Posting_Read (DP_CTL (Port));

      Registers.Unset_Mask (DP_CTL (Port), DP_CTL_DISPLAY_PORT_ENABLE);
      Registers.Posting_Read (DP_CTL (Port));
   end Off;

   ----------------------------------------------------------------------------

   procedure Pre_Training
     (Port_Cfg : in     Port_Config;
      Pipe     : in     Pipe_Index)
   is
      Sync_Polarity : constant Word32 :=
        (if Port_Cfg.Mode.H_Sync_Active_High
         then DP_CTL_HSYNC_ACTIVE_HIGH else 0) or
        (if Port_Cfg.Mode.V_Sync_Active_High
         then DP_CTL_VSYNC_ACTIVE_HIGH else 0);

      DP_Ctl_Value : Word32;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Registers.Read (DP_CTL (Port_Cfg.Port), DP_Ctl_Value);
      DP_Ctl_Value :=
         (DP_Ctl_Value and DP_CTL_PORT_DETECT) or
         DP_CTL_PORT_WIDTH (Port_Cfg.DP.Lane_Count) or
         DP_CTL_LINK_TRAIN (DP_Info.TP_1) or
         (if Port_Cfg.DP.Enhanced_Framing
          then DP_CTL_ENHANCED_FRAMING_ENABLE else 0) or
         DP_PIPE_SELECT (Pipe) or
         Sync_Polarity;

      -- The port has to be set up before it's enabled with a second
      -- write. Otherwise training fails with a freshly used power
      -- sequencer, according to i915.
      Registers.Write (DP_CTL (Port_Cfg.Port), DP_Ctl_Value);
      Registers.Posting_Read (DP_CTL (Port_Cfg.Port));
      Registers.Write
        (Register => DP_CTL (Port_Cfg.Port),
         Value    => DP_Ctl_Value or DP_CTL_DISPLAY_PORT_ENABLE);
      Registers.Posting_Read (DP_CTL (Port_Cfg.Port));
   end Pre_Training;

   procedure Train
     (Port_Cfg : in     Port_Config;
      Success  :    out Boolean)
   is
      function To_DP (Port : SoC_Port) return DP_Port is
        (case Port is
            when DIGI_B => DP_B,
            when DIGI_C => DP_C,
            when DIGI_D => DP_D);

      package Training is new DP_Training
        (TPS3_Supported    => False,
         T                 => SoC_Port,
         Aux_T             => DP_Port,
         Aux_Ch            => DP_Aux_Ch,
         DP_Info           => DP_Info,
         To_Aux            => To_DP,
         Max_V_Swing       => Max_V_Swing,
         Max_Pre_Emph      => Max_Pre_Emph,
         Set_Pattern       => Set_Training_Pattern,
         Set_Signal_Levels => Set_Signal_Levels,
         Off               => Off);
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      if Config.Has_CHV_PHY then
         DPIO_CHV.Wait_Port_Ready
           (Port           => Port_Cfg.Port,
            Unused_Lanes   =>
               DPIO_CHV.Unused_Lane_Mask (Port_Cfg.DP.Lane_Count));
      elsif Port_Cfg.Port in DPIO.DPIO_Port then
         DPIO.Wait_Port_Ready (Port_Cfg.Port);
      end if;

      Training.Train_DP
        (Port     => Port_Cfg.Port,
         Link     => Port_Cfg.DP,
         Success  => Success);
   end Train;

   ----------------------------------------------------------------------------

   procedure Kick_Power_Sequencer (Port : SoC_Port; Pipe : Pipe_Index)
   is
      DP_Ctl_Value : Word32;
   begin
      Registers.Read (DP_CTL (Port), DP_Ctl_Value);
      if (DP_Ctl_Value and DP_CTL_DISPLAY_PORT_ENABLE) /= 0 then
         return;
      end if;

      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      DP_Ctl_Value :=
         (DP_Ctl_Value and DP_CTL_PORT_DETECT) or
         DP_CTL_PORT_WIDTH (DP_Lane_Count_1) or
         DP_CTL_LINK_TRAIN (DP_Info.TP_1) or
         DP_PIPE_SELECT (Pipe);

      Registers.Write (DP_CTL (Port), DP_Ctl_Value);
      Registers.Posting_Read (DP_CTL (Port));
      Registers.Write
        (Register => DP_CTL (Port),
         Value    => DP_Ctl_Value or DP_CTL_DISPLAY_PORT_ENABLE);
      Registers.Posting_Read (DP_CTL (Port));
      Registers.Write (DP_CTL (Port), DP_Ctl_Value);
      Registers.Posting_Read (DP_CTL (Port));
   end Kick_Power_Sequencer;

   ----------------------------------------------------------------------------

   procedure All_Off
   is
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      for Port in SoC_Port range SoC_Port'First .. Last_Port loop
         Off (Port);
      end loop;
   end All_Off;

end HW.GFX.GMA.SoC.DP;
