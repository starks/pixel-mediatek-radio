// SPDX-License-Identifier: MIT
import java.util.Arrays;
import pixelradio.BandMask;

public final class VerifiedVectors {
    public static void main(String[] args) {
        int[] lte = {0x3300381a, 0x8100, 0x42, 0, 0, 0, 0, 0};
        int[] nrA = nrWords(0x33003850, 0x8120, 0x3062);
        int[] nrB = nrWords(0x2b0808d5, 0x81a0, 0x3042);

        verify(lte, new int[] {2}, new int[] {0x2, 0, 0, 0, 0, 0, 0, 0});
        verify(nrA, new int[] {66}, new int[] {0, 0, 0x2});
        verify(nrB, new int[] {66}, new int[] {0, 0, 0x2});
        verify(nrA, new int[] {41, 66}, new int[] {0, 0x100, 0x2});
        verify(nrB, new int[] {41, 66}, new int[] {0, 0x100, 0x2});

        // Includes bit 31 and the upper boundary of the 256-bit LTE mask.
        verify(new int[] {0x80000000, 0, 0, 0, 0, 0, 0, 0x80000000},
            new int[] {256}, new int[] {0, 0, 0, 0, 0, 0, 0, 0x80000000});
        System.out.println("All LTE/NR mask vectors and inverse deltas passed.");
    }

    private static int[] nrWords(int low, int middle, int high) {
        int[] words = new int[32];
        words[0] = low;
        words[1] = middle;
        words[2] = high;
        words[8] = 0x1a;
        return words;
    }

    private static void verify(int[] raw, int[] selected, int[] expectedPrefix) {
        BandMask original = BandMask.fromWords(raw);
        BandMask target = original.select(selected);
        equal(raw, original.toWords());
        equal(Arrays.copyOf(expectedPrefix, raw.length), target.toWords());
        equal(selected, target.bands());
        equal(target.toWords(), apply(original, original.deltaTo(target)));
        equal(raw, apply(target, target.deltaTo(original)));
    }

    private static int[] apply(BandMask current, BandMask.Delta delta) {
        int[] words = current.toWords();
        for (int band : delta.additions()) {
            int bit = band - 1;
            words[bit / 32] |= 1 << (bit % 32);
        }
        for (int band : delta.removals()) {
            int bit = band - 1;
            words[bit / 32] &= ~(1 << (bit % 32));
        }
        return words;
    }

    private static void equal(int[] expected, int[] actual) {
        if (!Arrays.equals(expected, actual)) {
            throw new AssertionError(Arrays.toString(expected) + " != " + Arrays.toString(actual));
        }
    }
}
