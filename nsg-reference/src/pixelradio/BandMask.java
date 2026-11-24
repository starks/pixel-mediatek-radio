// SPDX-License-Identifier: MIT
package pixelradio;

import java.util.BitSet;
import java.util.Objects;

/** Codec and delta planner for one LTE or NR band mask. */
public final class BandMask {
    private final int wordCount;
    private final BitSet bits;

    private BandMask(int wordCount, BitSet bits) {
        this.wordCount = wordCount;
        this.bits = bits;
    }

    public static BandMask fromWords(int... words) {
        if (words.length != 8 && words.length != 32) {
            throw new IllegalArgumentException("Expected 8 LTE or 32 NR words");
        }
        BitSet bits = new BitSet(words.length * Integer.SIZE);
        for (int index = 0; index < words.length; index++) {
            int remaining = words[index];
            while (remaining != 0) {
                int bit = Integer.numberOfTrailingZeros(remaining);
                bits.set(index * Integer.SIZE + bit);
                remaining &= remaining - 1;
            }
        }
        return new BandMask(words.length, bits);
    }

    public int[] toWords() {
        int[] words = new int[wordCount];
        for (int bit = bits.nextSetBit(0); bit >= 0; bit = bits.nextSetBit(bit + 1)) {
            words[bit / Integer.SIZE] |= 1 << (bit % Integer.SIZE);
        }
        return words;
    }

    public int[] bands() {
        return bandNumbers(bits);
    }

    /** Select bands from this baseline mask, preserving bands common to both sets. */
    public BandMask select(int... bands) {
        BitSet selected = new BitSet(wordCount * Integer.SIZE);
        for (int band : bands) {
            if (band < 1 || band > wordCount * Integer.SIZE) {
                throw new IllegalArgumentException("Band out of range: " + band);
            }
            if (bits.get(band - 1)) {
                selected.set(band - 1);
            }
        }
        if (selected.isEmpty()) {
            throw new IllegalArgumentException("Selection would leave the mask empty");
        }
        return new BandMask(wordCount, selected);
    }

    /** Build the sorted additions and removals from this mask to the target. */
    public Delta deltaTo(BandMask target) {
        Objects.requireNonNull(target);
        if (wordCount != target.wordCount) {
            throw new IllegalArgumentException("Mask widths differ");
        }
        BitSet additions = (BitSet) target.bits.clone();
        additions.andNot(bits);
        BitSet removals = (BitSet) bits.clone();
        removals.andNot(target.bits);
        return new Delta(bandNumbers(additions), bandNumbers(removals));
    }

    private static int[] bandNumbers(BitSet bits) {
        return bits.stream().map(index -> index + 1).toArray();
    }

    public static final class Delta {
        private final int[] additions;
        private final int[] removals;

        private Delta(int[] additions, int[] removals) {
            this.additions = additions;
            this.removals = removals;
        }

        public int[] additions() {
            return additions.clone();
        }

        public int[] removals() {
            return removals.clone();
        }
    }
}
