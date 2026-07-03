#ifndef SMCBridge_h
#define SMCBridge_h

#include <stdint.h>

/// Open a connection to AppleSMC. Returns 0 on success.
int smc_bridge_open(void);

/// Close the SMC connection.
void smc_bridge_close(void);

/// Read a float-type SMC key. Returns -1 on failure.
float smc_bridge_read_float(const char *key4);

/// Read a ui8-type SMC key. Returns -1 on failure.
int smc_bridge_read_ui8(const char *key4);

/// Write a float value to an SMC key. Returns 0 on success.
int smc_bridge_write_float(const char *key4, float value);

/// Write a ui8 value to an SMC key. Returns 0 on success.
int smc_bridge_write_ui8(const char *key4, uint8_t value);

#endif /* SMCBridge_h */
