package main

import "core:fmt"
import "core:os"

main::proc(){
    fmt.println("howdy, %v, %v from %v", os.args[1],os.args[2], os.args[0]);

}