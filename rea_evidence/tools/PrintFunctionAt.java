// Print Ghidra function boundaries for a list of (address, size, name) targets.
// Usage: PrintFunctionAt.java <targets.tsv>

import java.io.BufferedReader;
import java.io.FileReader;

import ghidra.app.script.GhidraScript;
import ghidra.program.model.address.Address;
import ghidra.program.model.listing.Function;

public class PrintFunctionAt extends GhidraScript {
    @Override
    public void run() throws Exception {
        String[] args = getScriptArgs();
        if (args.length < 1) {
            println("usage: PrintFunctionAt.java <targets.tsv>");
            return;
        }
        try (BufferedReader reader = new BufferedReader(new FileReader(args[0]))) {
            String line;
            while ((line = reader.readLine()) != null) {
                line = line.trim();
                if (line.isEmpty() || line.startsWith("#")) continue;
                String[] parts = line.split("\\t");
                if (parts.length < 3) continue;
                Address address = toAddr(Long.decode(parts[0]));
                Function at = getFunctionAt(address);
                Function containing = getFunctionContaining(address);
                println("TARGET " + parts[2] + " " + address);
                if (at == null) {
                    println("  at: null");
                } else {
                    println("  at: " + at.getName() + " entry=" + at.getEntryPoint()
                        + " body=" + at.getBody().getMinAddress() + ".."
                        + at.getBody().getMaxAddress());
                }
                if (containing == null) {
                    println("  containing: null");
                } else {
                    println("  containing: " + containing.getName() + " entry="
                        + containing.getEntryPoint() + " body="
                        + containing.getBody().getMinAddress() + ".."
                        + containing.getBody().getMaxAddress());
                }
            }
        }
    }
}
