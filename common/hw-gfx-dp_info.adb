--
-- Copyright (C) 2015-2017 secunet Security Networks AG
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

with Ada.Unchecked_Conversion;

with HW.Debug;
with GNAT.Source_Info;

with HW.GFX.DP_Defs;

use type HW.Word8;
use type HW.Word16;

package body HW.GFX.DP_Info is

   procedure Read_Caps
     (Link     : in out DP_Link;
      Port     : in     T;
      Success  :    out Boolean)
   is
      Data : DP_Defs.Aux_Payload;
      Length : DP_Defs.Aux_Payload_Length;

      Caps_Size : constant := 15;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Length := Caps_Size;
      Aux_Ch.Aux_Read
        (Port     => Port,
         Address  => 16#00000#,
         Length   => Length,
         Data     => Data,
         Success  => Success);
      Success := Success and Length = Caps_Size;

      if Length = Caps_Size then
         Link.Receiver_Caps.Rev := Data (0);
         case Data (1) is
            when 16#06# =>
               Link.Receiver_Caps.Max_Link_Rate := DP_Bandwidth_1_62;
            when 16#0a# =>
               Link.Receiver_Caps.Max_Link_Rate := DP_Bandwidth_2_7;
            when 16#14# =>
               Link.Receiver_Caps.Max_Link_Rate := DP_Bandwidth_5_4;
            when others =>
               if Data (1) > 16#14# then
                  Link.Receiver_Caps.Max_Link_Rate := DP_Bandwidth_5_4;
               else
                  Link.Receiver_Caps.Max_Link_Rate := DP_Bandwidth_1_62;
               end if;
         end case;
         case Data (2) and 16#1f# is
            when 0 | 1  =>
               Link.Receiver_Caps.Max_Lane_Count := DP_Lane_Count_1;
            when 2 | 3  =>
               Link.Receiver_Caps.Max_Lane_Count := DP_Lane_Count_2;
            when others =>
               Link.Receiver_Caps.Max_Lane_Count := DP_Lane_Count_4;
         end case;
         Link.Receiver_Caps.TPS3_Supported     := (Data (2) and 16#40#) /= 0;
         Link.Receiver_Caps.Enhanced_Framing   := (Data (2) and 16#80#) /= 0;
         Link.Receiver_Caps.No_Aux_Handshake   := (Data (3) and 16#40#) /= 0;
         Link.Receiver_Caps.Aux_RD_Interval    := Data (14) and 16#7f#;

         pragma Debug (Debug.New_Line);
         pragma Debug (Debug.Put_Line ("DPCD:"));
         pragma Debug (Debug.Put_Reg8 ("  Rev             ", Data (0)));
         pragma Debug (Debug.Put_Reg8 ("  Max_Link_Rate   ", Data (1)));
         pragma Debug (Debug.Put_Reg8 ("  Max_Lane_Count  ", Data (2) and 16#1f#));
         pragma Debug (Debug.Put_Reg8 ("  TPS3_Supported  ", Data (2) and 16#40#));
         pragma Debug (Debug.Put_Reg8 ("  Enhanced_Framing", Data (2) and 16#80#));
         pragma Debug (Debug.Put_Reg8 ("  No_Aux_Handshake", Data (3) and 16#40#));
         pragma Debug (Debug.Put_Reg8 ("  Aux_RD_Interval ", Data (14) and 16#7f#));
         pragma Debug (Debug.New_Line);
      end if;
   end Read_Caps;

   function Read_LE16
     (Raw_Payload : DP_Defs.Aux_Payload;
      Offset      : DP_Defs.Aux_Payload_Index)
      return Word16
   with
      Pre => Offset < DP_Defs.Aux_Payload_Index'Last
   is
   begin
      return Shift_Left (Word16 (Raw_Payload (Offset + 1)), 8) or
             Word16 (Raw_Payload (Offset));
   end Read_LE16;

   -- DPCD value is in units of 200 kHz of the link bit rate. Times 20 is
   -- the symbol rate in kHz, which is how i915 stores the same table.
   procedure Bandwidth_From_Rate
     (Rate_kHz :     Natural;
      BW       : out DP_Bandwidth;
      Valid    : out Boolean)
   is
   begin
      case Rate_kHz is
         when 162_000 => BW := DP_Bandwidth_1_62;
         when 216_000 => BW := DP_Bandwidth_2_16;
         when 270_000 => BW := DP_Bandwidth_2_7;
         when 324_000 => BW := DP_Bandwidth_3_24;
         when 432_000 => BW := DP_Bandwidth_4_32;
         when 540_000 => BW := DP_Bandwidth_5_4;
         when others  => BW := DP_Bandwidth'First;
      end case;
      Valid := Rate_kHz = Natural (DP_Symbol_Rate (BW) / 1_000);
   end Bandwidth_From_Rate;

   procedure Read_eDP_Rates
     (Link     : in out DP_Link;
      Port     : in     T)
   is
      Data : DP_Defs.Aux_Payload;
      Length : DP_Defs.Aux_Payload_Length;
      Success  : Boolean;

      Caps_Size : constant := 3;
      Rates_Size : constant := 16;
      eDP_Rev_1_4 : constant := 3;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Link.Receiver_Caps.Use_Rate_Select := False;
      Link.Receiver_Caps.Rates := No_eDP_Rates;
      Link.Use_Rate_Select := False;

      Length := Caps_Size;
      Aux_Ch.Aux_Read
          (Port    => Port,
          Address  => 16#00700#,
          Length   => Length,
          Data     => Data,
          Success  => Success);
      Success := Success and Length = Caps_Size;
      if not Success or Data (0) < eDP_Rev_1_4 then
         return;
      end if;

      Length := Rates_Size;
      Aux_Ch.Aux_Read
        (Port     => Port,
         Address  => 16#00010#,
         Length   => Length,
         Data     => Data,
         Success  => Success);
      Success := Success and Length = Rates_Size;
      if not Success then
         return;
      end if;

      pragma Debug (Debug.New_Line);
      pragma Debug (Debug.Put_Line ("DPCD eDP 1.4+ link rates:"));

      for I in eDP_Rate_Index loop
         declare
            Rate : constant Word16 :=
              Read_LE16 (Data, DP_Defs.Aux_Payload_Index (Natural (I) * 2));
            Rate_kHz : Natural;
            BW : DP_Bandwidth;
            Valid : Boolean;
         begin
            exit when Rate = 0;
            Rate_kHz := Natural (Rate) * 20;
            pragma Debug (Debug.Put (" - "));
            pragma Debug (Debug.Put_Int8 (Int8 (Natural (I))));
            pragma Debug (Debug.Put (": "));
            pragma Debug (Debug.Put_Word16 (Rate));
            pragma Debug (Debug.New_Line);
            Bandwidth_From_Rate (Rate_kHz, BW, Valid);
            if Valid then
               Link.Receiver_Caps.Rates (I) := (Valid => True, Bandwidth => BW);
               Link.Receiver_Caps.Use_Rate_Select := True;
            end if;
         end;
      end loop;
      pragma Debug (Debug.New_Line);
   end Read_eDP_Rates;

   procedure Minimum_Lane_Count
     (Link        : in out DP_Link;
      Mode        : in     Mode_Type;
      Success     :    out Boolean)
   with
      Depends => ((Link, Success) => (Link, Mode))
   is
      Lane_Pixel_Per_Second : constant Pos64 :=
        (((DP_Symbol_Rate (Link.Bandwidth) * 8) / 3) / Mode.BPC);
      Count : constant Pos64 :=
         Div_Round_Up (Mode.Dotclock, Lane_Pixel_Per_Second);
   begin
      Success := True;
      case Count is
         when 1      => Link.Lane_Count := DP_Lane_Count_1;
         when 2      => Link.Lane_Count := DP_Lane_Count_2;
         when 3 | 4  => Link.Lane_Count := DP_Lane_Count_4;
         when others => Success := False;
      end case;
   end Minimum_Lane_Count;

   -- LINK_BW_SET only encodes these three. The others need LINK_RATE_SET.
   function Is_Link_BW_Rate (BW : DP_Bandwidth) return Boolean is
     (BW in DP_Bandwidth_1_62 | DP_Bandwidth_2_7 | DP_Bandwidth_5_4);

   procedure Preferred_Link_Setting
     (Link        : in out DP_Link;
      Mode        : in     Mode_Type;
      Success     :    out Boolean)
   is
   begin
      Link.Enhanced_Framing := Link.Receiver_Caps.Enhanced_Framing;
      Link.Use_Rate_Select := False;

      -- eDP 1.4: lowest advertised rate that fits the mode, then the
      -- fewest lanes. i915 does the same when it is not forcing max params.
      if Link.Receiver_Caps.Use_Rate_Select then
         Success := False;
         for BW in DP_Bandwidth loop
            exit when Success;
            for I in eDP_Rate_Index loop
               if Link.Receiver_Caps.Rates (I).Valid and then
                  Link.Receiver_Caps.Rates (I).Bandwidth = BW
               then
                  Link.Bandwidth := BW;
                  Link.Rate_Select := I;
                  Minimum_Lane_Count (Link, Mode, Success);
                  Success := Success and
                     Link.Lane_Count <= Link.Receiver_Caps.Max_Lane_Count;
                  if Success then
                     Link.Use_Rate_Select := True;
                     exit;
                  end if;
               end if;
            end loop;
         end loop;
      else
         Link.Bandwidth := Link.Receiver_Caps.Max_Link_Rate;

         Minimum_Lane_Count (Link, Mode, Success);

         Success := Success and
                     Link.Lane_Count <= Link.Receiver_Caps.Max_Lane_Count;
      end if;

      pragma Debug (not Success, Debug.Put_Line
        ("Mode requirements exceed available bandwidth!"));
   end Preferred_Link_Setting;

   procedure Next_Link_Setting
     (Link        : in out DP_Link;
      Mode        : in     Mode_Type;
      Success     :    out Boolean)
   is
   begin
      if Link.Use_Rate_Select then
         -- Training failed at the narrow setting. Retry once at the
         -- highest advertised rate and the sink's maximum lane count.
         declare
            Max_BW  : DP_Bandwidth := Link.Bandwidth;
            Max_Idx : eDP_Rate_Index := Link.Rate_Select;
            Found   : Boolean := False;
         begin
            for BW in reverse DP_Bandwidth loop
               exit when Found;
               for I in eDP_Rate_Index loop
                  if Link.Receiver_Caps.Rates (I).Valid and then
                     Link.Receiver_Caps.Rates (I).Bandwidth = BW
                  then
                     Max_BW := BW;
                     Max_Idx := I;
                     Found := True;
                     exit;
                  end if;
               end loop;
            end loop;

            if Found and then
               (Link.Bandwidth /= Max_BW or
                Link.Lane_Count /= Link.Receiver_Caps.Max_Lane_Count)
            then
               Link.Bandwidth := Max_BW;
               Link.Rate_Select := Max_Idx;
               Link.Lane_Count := Link.Receiver_Caps.Max_Lane_Count;
               Success := True;
            else
               Success := False;
            end if;
         end;
      elsif Link.Bandwidth > DP_Bandwidth'First then
         loop
            Link.Bandwidth := DP_Bandwidth'Pred (Link.Bandwidth);
            exit when Is_Link_BW_Rate (Link.Bandwidth);
            exit when Link.Bandwidth = DP_Bandwidth'First;
         end loop;

         if Is_Link_BW_Rate (Link.Bandwidth) then
            Minimum_Lane_Count (Link, Mode, Success);

            Success := Success and
                       Link.Lane_Count <= Link.Receiver_Caps.Max_Lane_Count;
         else
            Success := False;
         end if;
      else
         Success := False;
      end if;
   end Next_Link_Setting;

   procedure Dump_Link_Setting (Link : DP_Link)
   is
   begin
      Debug.Put ("Trying DP settings: Symbol Rate = ");
      Debug.Put_Int32 (Int32 (DP_Symbol_Rate (Link.Bandwidth)));
      Debug.Put ("; Lane Count = ");
      Debug.Put_Int32 (Int32 (Lane_Count_As_Integer (Link.Lane_Count)));
      if Link.Use_Rate_Select then
         Debug.Put ("; LINK_RATE_SET = ");
         Debug.Put_Int32 (Int32 (Natural (Link.Rate_Select)));
      end if;
      Debug.New_Line;
      Debug.New_Line;
   end Dump_Link_Setting;

   ----------------------------------------------------------------------------

   procedure Calculate_M_N
     (Link     : in     DP_Link;
      Mode     : in     Mode_Type;
      Data_M   :    out M_Type;
      Data_N   :    out N_Type;
      Link_M   :    out M_Type;
      Link_N   :    out N_Type)
   is
      DATA_N_MAX : constant := 16#800000#;
      LINK_N_MAX : constant := 16#100000#;

      subtype Calc_M_Type is Int64 range 0 .. 2 ** 38;
      subtype Calc_N_Type is Int64 range 0 .. 2 ** 38;
      subtype N_Rounded_Type is Int64 range
         0 .. Int64'Max (DATA_N_MAX, LINK_N_MAX);

      M : Calc_M_Type;
      N : Calc_N_Type;

      procedure Cancel_M_N
        (M     : in out Calc_M_Type;
         N     : in out Calc_N_Type;
         N_Max : in     N_Rounded_Type)
      with
         Depends => ((M, N) => (M, N, N_Max)),
         Pre => (N > 0 and M in 0 .. Calc_M_Type'Last / 2),
         Post => (M <= M_N_Max and N <= M_N_Max)
      is
         Orig_N : constant Calc_N_Type := N;

         function Round_N (N : Calc_N_Type) return N_Rounded_Type
         with
            Post => (Round_N'Result <= N * 2)
         is
            RN : Calc_N_Type;
            RN2 : Calc_N_Type := N_Max;
         begin
            loop
               RN := RN2;
               RN2 := RN2 / 2;
               exit when RN2 < N;
               pragma Loop_Invariant (RN2 = RN / 2 and RN2 in N .. N_Max);
            end loop;
            return RN;
         end Round_N;
      begin
         N := Round_N (N);

         -- The automatic provers need a little nudge here.
         pragma Assert
            (if M <= Calc_M_Type'Last / 2 and
                N <= Orig_N * 2 and
                Orig_N > 0 and
                M > 0
             then
                M * N / Orig_N <= Calc_M_Type'Last);

         pragma Annotate (GNATprove, False_Positive,
            "assertion might fail",
            "The property cannot be proven automatically. An Isabelle proof is included as an axiom");

         M := M * N / Orig_N;

         -- This loop is never hit for sane values (i.e. M <= N) but
         -- we have to make sure returned values are always in range.
         while M > M_N_Max loop
            pragma Loop_Invariant (N <= M_N_Max);
            M := M / 2;
            N := N / 2;
         end loop;
      end Cancel_M_N;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      pragma Assert (3
                     * Mode.BPC
                     * Mode.Dotclock
                     in Pos64);
      M := 3
           * Mode.BPC
           * Mode.Dotclock;

      pragma Assert (8
                     * DP_Symbol_Rate (Link.Bandwidth)
                     * Lane_Count_As_Integer (Link.Lane_Count)
                     in Pos64);
      N := 8
           * DP_Symbol_Rate (Link.Bandwidth)
           * Lane_Count_As_Integer (Link.Lane_Count);

      Cancel_M_N (M, N, DATA_N_MAX);
      Data_M := M;
      Data_N := N;

      -------------------------------------------------------------------

      M := Pos64 (Mode.Dotclock);
      N := Pos64 (DP_Symbol_Rate (Link.Bandwidth));

      Cancel_M_N (M, N, LINK_N_MAX);
      Link_M := M;
      Link_N := N;
   end Calculate_M_N;

   ----------------------------------------------------------------------------

   procedure Read_Link_Status
     (Port     : in     T;
      Status   :    out Link_Status;
      Success  :    out Boolean)
   is
      subtype Status_Index is DP_Defs.Aux_Payload_Index range 0 .. 5;
      subtype Status_Buffer is Buffer (Status_Index)
      with
         Object_Size => 48;
      function Buffer_As_Status is new Ada.Unchecked_Conversion
        (Source => Status_Buffer, Target => Link_Status);

      Data : DP_Defs.Aux_Payload;
      Length : DP_Defs.Aux_Payload_Length;
   begin
      pragma Debug (Debug.Put_Line (GNAT.Source_Info.Enclosing_Entity));

      Length := Status_Index'Last + 1;
      Aux_Ch.Aux_Read
        (Port     => Port,
         Address  => 16#00202#,
         Length   => Length,
         Data     => Data,
         Success  => Success);
      Success := Success and Length = Status_Index'Last + 1;
      Status := Buffer_As_Status (Data (Status_Index));
   end Read_Link_Status;

   function All_CR_Done
     (Status   : Link_Status;
      Link     : DP_Link)
      return Boolean
   is
      CR_Done : Boolean := True;
   begin
      for Lane in Lane_Index
         range 0 .. Lane_Index (Lane_Count_As_Integer (Link.Lane_Count) - 1)
      loop
         CR_Done := CR_Done and Status.Lanes (Lane).CR_Done;
      end loop;
      return CR_Done;
   end All_CR_Done;

   function All_EQ_Done
     (Status   : Link_Status;
      Link     : DP_Link)
      return Boolean
   is
      EQ_Done : Boolean := True;
   begin
      for Lane in Lane_Index
         range 0 .. Lane_Index (Lane_Count_As_Integer (Link.Lane_Count) - 1)
      loop
         EQ_Done := EQ_Done and Status.Lanes (Lane).CR_Done
                            and Status.Lanes (Lane).Channel_EQ_Done
                            and Status.Lanes (Lane).Symbol_Locked;
      end loop;
      return EQ_Done and Status.Interlane_Align_Done;
   end All_EQ_Done;

   function Max_Requested_VS
     (Status   : Link_Status;
      Link     : DP_Link)
      return DP_Voltage_Swing
   is
      VS : DP_Voltage_Swing := DP_Voltage_Swing'First;
   begin
      for Lane in Lane_Index
         range 0 .. Lane_Index (Lane_Count_As_Integer (Link.Lane_Count) - 1)
      loop
         if Status.Adjust_Requests (Lane).Voltage_Swing > VS then
            VS := Status.Adjust_Requests (Lane).Voltage_Swing;
         end if;
      end loop;
      return VS;
   end Max_Requested_VS;

   function Max_Requested_Emph
     (Status   : Link_Status;
      Link     : DP_Link)
      return DP_Pre_Emph
   is
      Emph : DP_Pre_Emph := DP_Pre_Emph'First;
   begin
      for Lane in Lane_Index
         range 0 .. Lane_Index (Lane_Count_As_Integer (Link.Lane_Count) - 1)
      loop
         if Status.Adjust_Requests (Lane).Pre_Emph > Emph then
            Emph := Status.Adjust_Requests (Lane).Pre_Emph;
         end if;
      end loop;
      return Emph;
   end Max_Requested_Emph;

end HW.GFX.DP_Info;
