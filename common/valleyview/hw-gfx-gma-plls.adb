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

with HW.GFX.GMA.Registers;

package body HW.GFX.GMA.PLLs
with
   Refined_State => (State => null)
is

   DPLL_REF_CLK_ENABLE_VLV     : constant := 1 * 2 ** 29;
   DPLL_VGA_MODE_DIS           : constant := 1 * 2 ** 28;
   DPLL_INTEGRATED_CRI_CLK_VLV : constant := 1 * 2 ** 14;
   DPLL_INTEGRATED_REF_CLK_VLV : constant := 1 * 2 ** 13;

   procedure Initialize is null;

   procedure Enable_Refclk
   is
   begin
      -- Enable Refclk, this needs to be done early
      Registers.Set_Mask
        (Register => Registers.GMCH_DPLL_A,
         Mask     => DPLL_VGA_MODE_DIS or
                     DPLL_REF_CLK_ENABLE_VLV or
                     DPLL_INTEGRATED_REF_CLK_VLV);
      Registers.Set_Mask
        (Register => Registers.GMCH_DPLL_B,
         Mask     => DPLL_VGA_MODE_DIS or
                     DPLL_REF_CLK_ENABLE_VLV or
                     DPLL_INTEGRATED_CRI_CLK_VLV or
                     DPLL_INTEGRATED_REF_CLK_VLV);
   end Enable_Refclk;

   pragma Warnings (GNATprove, Off, "unused variable ""Port_Cfg""",
                    Reason => "Needed for a common interface");
   procedure Alloc
     (Port_Cfg : in     Port_Config;
      PLL      :    out T;
      Success  :    out Boolean)
   is
   begin
      PLL := Invalid;
      Success := False;
   end Alloc;
   pragma Warnings (GNATprove, On, "unused variable ""Port_Cfg""");

   procedure Free (PLL : T) is null;

   procedure All_Off is null;

   function Register_Value (PLL : T) return Word32 is (0);

end HW.GFX.GMA.PLLs;
