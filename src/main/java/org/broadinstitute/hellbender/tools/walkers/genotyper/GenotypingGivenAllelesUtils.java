package org.broadinstitute.hellbender.tools.walkers.genotyper;

import com.google.common.annotations.VisibleForTesting;
import htsjdk.samtools.util.Locatable;
import htsjdk.variant.variantcontext.Allele;
import htsjdk.variant.variantcontext.VariantContext;
import org.broadinstitute.hellbender.engine.FeatureContext;
import org.broadinstitute.hellbender.engine.FeatureInput;
import org.broadinstitute.hellbender.utils.GenomeLoc;
import org.broadinstitute.hellbender.utils.SimpleInterval;
import org.broadinstitute.hellbender.utils.Utils;
import org.broadinstitute.hellbender.utils.haplotype.Haplotype;
import org.broadinstitute.hellbender.utils.variant.GATKVariantContextUtils;

import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.stream.Collectors;

/**
 * Compendium of utils to work in GENOTYPE_GIVEN_ALLELES mode.
 */
public final class GenotypingGivenAllelesUtils {

    /**
     * Composes the given allele variant-context providing information about the rods and reference location.
     * @param tracker the meta data tracker.
     * @param loc the query location.
     * @param snpsOnly whether we only should consider SNP variation.
     * @param keepFiltered whether to include filtered variants
     * @param allelesBinding the target variation context binding containing the given alleles.
     * @return never {@code null}
     */
    public static VariantContext composeGivenAllelesVariantContextFromRod(final FeatureContext tracker,
                                                                          final Locatable loc,
                                                                          final boolean snpsOnly,
                                                                          final boolean keepFiltered,
                                                                          final FeatureInput<VariantContext> allelesBinding) {
        Utils.nonNull(tracker, "tracker may not be null");
        Utils.nonNull(loc, "location may not be null");
        Utils.nonNull(allelesBinding, "alleles binding may not be null");

        final List<VariantContext> variantContextsInFeatureContext = tracker.getValues(allelesBinding, new SimpleInterval(loc));
        return composeGivenAllelesVariantContextFromVariantList(variantContextsInFeatureContext, loc, snpsOnly, keepFiltered);
    }

    @VisibleForTesting
    protected static VariantContext composeGivenAllelesVariantContextFromVariantList(final List<VariantContext> variantContextsInFeatureContext, final Locatable loc, final boolean snpsOnly, final boolean keepFiltered) {
        final List<VariantContext> rodVcsAtLoc = variantContextsInFeatureContext
                .stream()
                .filter(vc -> vc.getStart() == loc.getStart() &&
                        (keepFiltered || vc.isNotFiltered()) &&
                        (!snpsOnly || vc.isSNP()))
                .collect(Collectors.toList());


        if (rodVcsAtLoc.isEmpty()) {
            return null;
        }
        final List<String> haplotypeSources = rodVcsAtLoc.stream().map(VariantContext::getSource).collect(Collectors.toList());
        final VariantContext mergedVc = GATKVariantContextUtils.simpleMerge(rodVcsAtLoc, haplotypeSources,
                GATKVariantContextUtils.FilteredRecordMergeType.KEEP_IF_ANY_UNFILTERED,
                GATKVariantContextUtils.GenotypeMergeType.PRIORITIZE, false, false, null, false, false);

        return mergedVc;
    }

    /**
     * Create the list of artificial GGA-mode haplotypes by injecting each of the provided alternate alleles into the reference haplotype
     *
     * @param refHaplotype the reference haplotype
     * @param givenHaplotypes the list of alternate alleles in VariantContexts
     * @param activeRegionWindow the window containing the reference haplotype
     *
     * @return a non-null list of haplotypes
     */
    public static List<Haplotype> composeGivenHaplotypes(final Haplotype refHaplotype, final List<VariantContext> givenHaplotypes, final GenomeLoc activeRegionWindow) {
        Utils.nonNull(refHaplotype, "reference haplotype may not be null");
        Utils.nonNull(givenHaplotypes, "given haplotypes may not be null");
        Utils.nonNull(activeRegionWindow, "active region window may not be null");
        Utils.validateArg(activeRegionWindow.size() == refHaplotype.length(), "inconsistent reference haplotype and active region window");

        final Set<Haplotype> returnHaplotypes = new LinkedHashSet<>();
        final int activeRegionStart = refHaplotype.getAlignmentStartHapwrtRef();

        for( final VariantContext compVC : givenHaplotypes ) {
            Utils.validateArg(GATKVariantContextUtils.overlapsRegion(compVC, activeRegionWindow),
                    " some variant provided does not overlap with active region window");
            for( final Allele compAltAllele : compVC.getAlternateAlleles() ) {
                final Haplotype insertedRefHaplotype = refHaplotype.insertAllele(compVC.getReference(), compAltAllele, activeRegionStart + compVC.getStart() - activeRegionWindow.getStart(), compVC.getStart());
                if( insertedRefHaplotype != null ) { // can be null if the requested allele can't be inserted into the haplotype
                    returnHaplotypes.add(insertedRefHaplotype);
                }
            }
        }

        return new ArrayList<>(returnHaplotypes);
    }
}
