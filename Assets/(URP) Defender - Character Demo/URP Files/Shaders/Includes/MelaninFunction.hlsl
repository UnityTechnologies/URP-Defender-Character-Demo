/*
-----------------------------------------------------------------------------------------------------
Melanin reference:
-----------------------------------------------------------------------------------------------------
Disney/Pixar:
https://rmanwiki.pixar.com/display/REN/PxrHairColor

Chaosgroup Vray:
https://www.chaosgroup.com/blog/v-ray-next-the-science-behind-the-new-hair-shader

Frostbite:
https://www.youtube.com/watch?v=qQxtZ_M69PQ

Maya Anold:
https://www.youtube.com/watch?v=1YstS2rFs4w

-----------------------------------------------------------------------------------------------------
Melanin Description:
-----------------------------------------------------------------------------------------------------
The melanin content of the hair fiber. Use this to generated natural colors for mammalian hair.
0 will give white hair, 0.2-0.4 blonde, 0.4-0.6 red, 0.6-0.8 brown and 0.8-1.0 black hair.
If you want to set the color of the hair with a texture map, set this to 0 and use the Dye color parameter.
*/
#ifndef UNIVERSAL_PIPELINE
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#endif

#define HAIR_COLOR_ABSORPTION 5.888414 

real3 Pow2(real3 x)
{
	return x * x;
}

// Reference: An Energy-Conserving Hair Reflectance Model
// Melanin [0..1] range
void GetHairColorFromMelanin_float(real InMelanin, real InRedness, real3 InDyeColor, out real3 OutColor)
{
	InMelanin = saturate(InMelanin);
	InRedness = saturate(InRedness);
	real Melanin	 = -log(max(1 - InMelanin, 0.0001));
	real Eumelanin	 = Melanin * (1 - InRedness);
	real Pheomelanin = Melanin * InRedness;

	// Compute a perceptualy linear absorption weight from MelaninDensity
	real3 DyeAbsorption = Pow2(log(saturate(InDyeColor))/ HAIR_COLOR_ABSORPTION);
	real3 Absorption = Eumelanin * real3(0.506, 0.841, 1.653) + Pheomelanin * real3(0.343, 0.733, 1.924);
	// Beer's Law - absorption term
	OutColor = exp(-sqrt(Absorption + DyeAbsorption)* HAIR_COLOR_ABSORPTION);
}

void GetHairColorFromMelanin_half(half InMelanin, half InRedness, half3 InDyeColor, out half3 OutColor)
{
	GetHairColorFromMelanin_float(InMelanin, InRedness, InDyeColor, OutColor);
}