#include "hardware.h"

module PlatformP @safe() {
  provides interface Init;
  uses interface Init as MoteInit;
  uses interface Init as LedsInit;
  uses interface Init as Msp430ClockInit;
  
}
implementation {
  command error_t Init.init() {
    WDTCTL = WDTPW + WDTHOLD;
    call Msp430ClockInit.init();
    call MoteInit.init();
    call LedsInit.init();
    return SUCCESS;
  }


  default command error_t LedsInit.init() { return SUCCESS; }
}
