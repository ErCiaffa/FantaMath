function out = releaseTax(valoreSvincoloBase, costo, isObbligatorio, params)
%RELEASETAX Tassazione svincolo (2026-08-04, adattato da raw_data/FantaMath/+src/+engine/releaseTax.m
% -- fase "tassazione-svincolo" di un altro branch, mai mersa in FantaManager -- con l'aggiunta
% del recupero minusvalenza, richiesto esplicitamente e assente nell'originale).
%
% Plusvalenza = max(0, valoreSvincoloBase - costo)
% Minusvalenza = max(0, costo - valoreSvincoloBase)
% AliquotaValore = params.taxEstero (obbligatorio) | params.taxDecisionale (scelto)
% TassaValore = AliquotaValore * valoreSvincoloBase
% TassaPlusvalenza = params.taxPlusvalenza * Plusvalenza
% RecuperoMinusvalenza = params.taxMinusvalenza * Minusvalenza
% IncassoNetto = max(0, valoreSvincoloBase - TassaValore - TassaPlusvalenza + RecuperoMinusvalenza - params.taxFee)
    arguments
        valoreSvincoloBase (1,1) double {mustBeNonnegative, mustBeFinite}
        costo (1,1) double {mustBeNonnegative, mustBeFinite}
        isObbligatorio (1,1) logical
        params (1,1) struct
    end

    plusvalenza = max(0, valoreSvincoloBase - costo);
    minusvalenza = max(0, costo - valoreSvincoloBase);
    if isObbligatorio
        aliquotaValore = params.taxEstero;
    else
        aliquotaValore = params.taxDecisionale;
    end
    tassaValore = aliquotaValore * valoreSvincoloBase;
    tassaPlusvalenza = params.taxPlusvalenza * plusvalenza;
    recuperoMinusvalenza = params.taxMinusvalenza * minusvalenza;
    incassoNetto = max(0, valoreSvincoloBase - tassaValore - tassaPlusvalenza + recuperoMinusvalenza - params.taxFee);

    out = struct();
    out.Plusvalenza = plusvalenza;
    out.Minusvalenza = minusvalenza;
    out.TassaValore = tassaValore;
    out.TassaPlusvalenza = tassaPlusvalenza;
    out.RecuperoMinusvalenza = recuperoMinusvalenza;
    out.IncassoNetto = incassoNetto;
    out.AliquotaValore = aliquotaValore;
end
