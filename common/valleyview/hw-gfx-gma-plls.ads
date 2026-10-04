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

private package HW.GFX.GMA.PLLs
with
   Abstract_State => (State with Part_Of => GMA.State)
is

   -- The DPLLs of Valleyview are bound to the pipes and have to be
   -- enabled in between the DPIO PHY setup steps. Hence, Alloc only
   -- checks that a configuration is feasible and the connectors enable
   -- the DPLL of their pipe with On() and Off().

   -- XXX: Types should be private (but that triggers a bug in SPARK GPL 2016)
   type T is (Invalid_PLL, Pipe_DPLL);
   Invalid : constant T := Invalid_PLL;

   subtype DPLL_Pipe is Pipe_Index range Primary .. Secondary;

   procedure Initialize
   with
      Global => (Output => State);

   procedure Alloc
     (Port_Cfg : in     Port_Config;
      PLL      :    out T;
      Success  :    out Boolean);

   procedure Free (PLL : T);

   procedure All_Off;

   function Register_Value (PLL : T) return Word32;

   procedure On
     (Pipe     : in     DPLL_Pipe;
      Port_Cfg : in     Port_Config;
      Success  :    out Boolean);

   -- Run the DPLL at the DP RBR rate, without any port, unless it's
   -- already running. Needed to kick the panel power sequencer of a pipe.
   procedure On_RBR
     (Pipe     : in     DPLL_Pipe;
      Was_On   :    out Boolean;
      Success  :    out Boolean);

   procedure Off (Pipe : DPLL_Pipe);

end HW.GFX.GMA.PLLs;
