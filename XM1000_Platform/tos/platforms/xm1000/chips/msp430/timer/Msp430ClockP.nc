//$Id: Msp430ClockP.nc,v 1.9 2010-06-29 22:07:45 scipio Exp $

/*
 * Copyright (c) 2011 ADVANTICSYS, SL
 * Copyright (c) 2000-2003 The Regents of the University of California.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * - Redistributions of source code must retain the above copyright
 *   notice, this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright
 *   notice, this list of conditions and the following disclaimer in the
 *   documentation and/or other materials provided with the
 *   distribution.
 * - Neither the name of the copyright holders nor the names of
 *   its contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE
 * COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 */

/**
 * @author Cory Sharp <cssharp@eecs.berkeley.edu>
 * @author Manuel Fernandez <manuel.fernandez@advanticsys.com>
 */

#include <Msp430DcoSpec.h>
#include "Msp430Timer.h"

module Msp430ClockP @safe()
{
  provides interface Init;
  provides interface Msp430ClockInit;
  provides interface McuPowerOverride;
}
implementation
{
  MSP430REG_NORACE(IE1);
  MSP430REG_NORACE(TACTL);
  MSP430REG_NORACE(TAIV);
  MSP430REG_NORACE(TBCTL);
  MSP430REG_NORACE(TBIV);

  #if defined(__MSP430_HAS_BC2__)	/* basic clock module+ */
  #define FIRST_STEP 0x1000
  #else					/* orig basic clock module */
  #define RSEL3 0
  #define FIRST_STEP 0x800
  #endif

  enum
  {
    DCOX = DCO2 + DCO1 + DCO0,
    MODX = MOD4 + MOD3 + MOD2 + MOD1 + MOD0,
    RSELX = RSEL3 + RSEL2 + RSEL1 + RSEL0,
    ACLK_CALIB_PERIOD = 8,
    TARGET_DCO_DELTA = (TARGET_DCO_KHZ / ACLK_KHZ) * ACLK_CALIB_PERIOD,
  };

async command mcu_power_t McuPowerOverride.lowestState() {
    return MSP430_POWER_LPM3;
  }
  command void Msp430ClockInit.defaultSetupDcoCalibrate()
  {
    /* WARNING: Haven't verified that CCI2B, selected via CCIS_1 below, maps
     * to ACLK for all msp430 chips, as required by this component.
     */

    BCSCTL1 |= DIVA_3;			/* ACLK/8 */
    TACCTL2 = CM_1 + CCIS_1 + CAP;	/* Capture on rising ACLK */
    TACTL = TASSEL_2 + MC_2 + TACLR;	/* Continuous mode, source SMCLK */
    
   }

  command void Msp430ClockInit.defaultInitClocks()
  {
    //const unsigned int divider = TARGET_DCO_KHZ / 1000;

    BCSCTL1 &= ~DIVA_3;			/* ACLK = LFXT1/1 */

	  	
    /* TinyOS upper layers assumes that SMCLK has been set to 1,048,576HZ.  If
     * DCOCLK has been set to 1x, 2x, 4x or 8x this value, we can set SMCLK to
     * the expected value.   Platforms using different clocks will have to set
     * the divider or adjust its upper layers accordingly.
     */
    //if (divider >= 8)
      BCSCTL2 = DIVS_3;
  /*  else if (divider >= 4)
      BCSCTL2 = DIVS_2;
    else if (divider >= 2)
      BCSCTL2 = DIVS_1;
    else
      BCSCTL2 = DIVS_0;
*/
    /* No interrupt for oscillator fault */
    CLR_FLAG( IE1, OFIE );
  }

  command void Msp430ClockInit.defaultInitTimerA()
  {
    TACTL = TASSEL_2 | TACLR | TAIE;
  }

  command void Msp430ClockInit.defaultInitTimerB()
  {
    TBCTL = TBSSEL_1 | TACLR | TBIE;
  }

  default event void Msp430ClockInit.setupDcoCalibrate()
  {
    call Msp430ClockInit.defaultSetupDcoCalibrate();
  }

  default event void Msp430ClockInit.initClocks()
  {
    call Msp430ClockInit.defaultInitClocks();
  }

  default event void Msp430ClockInit.initTimerA()
  {
    call Msp430ClockInit.defaultInitTimerA();
  }

  default event void Msp430ClockInit.initTimerB()
  {
    call Msp430ClockInit.defaultInitTimerB();
  }


  void startTimerA()
  {
    /* Start TimerA for continuous mode */
    TACTL = (TACTL & ~MC_3) | MC_2;
  }


  void stopTimerA()
  {
    TACTL &= ~MC_3;
  }

  void startTimerB()
  {
    /* Start TimerB in continuous mode */
    TBCTL = (TBCTL & ~MC_3) | MC_2;
  }

  void stopTimerB()
  {
    TBCTL &= ~MC_3;
  }

  void set_dco_calib(uint16_t calib)
  {
    BCSCTL1 = (BCSCTL1 & ~RSELX) | ((calib >> 8) & RSELX);
    DCOCTL = calib & 0xff;
  }

  uint16_t test_calib_busywait_delta(uint16_t calib)
  {
    uint16_t capture;

    set_dco_calib(calib);

    /* Capture first TAR on ACLK boundary */
    while (!(CCIFG & TACCTL2));
    TACCTL2 &= ~CCIFG;
    capture = TACCR2;

    /* Capture next TAR */
    while (!(CCIFG & TACCTL2));
    TACCTL2 &= ~CCIFG;

    /* Return TimerA ticks in LFXT1/8 time window */
    return TACCR2 - capture;
  }

  void busyCalibrateDco()
  {
    /* calib are these bits MSb to LSb: RSELx DCOx MODx */
    uint16_t calib;
    uint16_t step;

    for (calib = 0, step = FIRST_STEP; step != 0; step >>= 1) {
      // if the step is not past the target, commit it
      if (test_calib_busywait_delta(calib | step) <= TARGET_DCO_DELTA )
        calib |= step;
    }

    /* if DCOx is all 1's in calib, then MODx must be set to 0 */
    if ((calib & DCOX) == DCOX)
      calib &= ~RSELX;

    set_dco_calib( calib );
    TACCTL2 = 0;				/* Stop TACCR2 */
    TACTL = 0;					/* Stop Timer_A */
  }

  command error_t Init.init()
  {
    /* Reset timers and clear interrupt vectors */
    TACTL = TACLR;
    TAIV  = 0;
    TBCTL = TBCLR;
    TBIV  = 0;

    atomic
    {
      signal Msp430ClockInit.setupDcoCalibrate();
      busyCalibrateDco();
      signal Msp430ClockInit.initClocks();
      signal Msp430ClockInit.initTimerA();
      signal Msp430ClockInit.initTimerB();
      startTimerA();
      startTimerB();
    }

    return SUCCESS;
  }
}
