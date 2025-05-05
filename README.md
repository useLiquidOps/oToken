# LiquidOps oToken

The oToken module is a core component of the LiquidOps protocol, based on the [AOS module](https://github.com/permaweb/aos). It is used to spawn oToken processes that enable pooling a specific collateral, which in return earns interest when borrowed. oTokens communicate with each other and the [controller](https://github.com/useLiquidOps/controller) to syncronise the user's position, etc. in the protocol.

## Note about tests

The current integration tests are not complete and will be subject to refactor.
