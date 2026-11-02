/* =========================================================
   PACKAGE: PKG_ANIMAL
   Responsabilidade: consultas de animais e serializacao JSON.
   Depende de T_ANIMAL, T_BREED e T_SPECIES.
========================================================= */

CREATE OR REPLACE PACKAGE PKG_ANIMAL AS

    FUNCTION FN_ANIMAL_TO_JSON (
        P_ID             IN T_ANIMAL.ID%TYPE,
        P_NAME           IN T_ANIMAL.NAME%TYPE,
        P_NICKNAME       IN T_ANIMAL.NICKNAME%TYPE,
        P_GENDER         IN T_ANIMAL.GENDER%TYPE,
        P_BIRTH_DATE     IN T_ANIMAL.BIRTH_DATE%TYPE,
        P_RGA            IN T_ANIMAL.RGA%TYPE,
        P_MICROCHIP_CODE IN T_ANIMAL.MICROCHIP_CODE%TYPE,
        P_IS_NEUTERED    IN T_ANIMAL.IS_NEUTERED%TYPE,
        P_WEIGHT         IN T_ANIMAL.WEIGHT%TYPE,
        P_HEIGHT         IN T_ANIMAL.HEIGHT%TYPE,
        P_COLOR          IN T_ANIMAL.COLOR%TYPE,
        P_STATUS         IN T_ANIMAL.STATUS%TYPE,
        P_SPECIES_NAME   IN T_SPECIES.NAME%TYPE,
        P_BREED_NAME     IN T_BREED.NAME%TYPE,
        P_BREED_SIZE     IN T_BREED.PORT%TYPE
    ) RETURN VARCHAR2;

    PROCEDURE PR_LISTAR_ANIMAIS_JSON (
        P_SPECIES_NAME IN T_SPECIES.NAME%TYPE DEFAULT NULL
    );

END PKG_ANIMAL;
/

CREATE OR REPLACE PACKAGE BODY PKG_ANIMAL AS

    /* Rotina interna: escapa strings para JSON (nao exposta no package). */
    FUNCTION FN_JSON_STRING(P_VALOR IN VARCHAR2) RETURN VARCHAR2 IS
        V_VALOR VARCHAR2(32767);
    BEGIN
        IF P_VALOR IS NULL THEN
            RETURN 'null';
        END IF;

        V_VALOR := REPLACE(P_VALOR, '\', '\\');
        V_VALOR := REPLACE(V_VALOR, '"', '\"');
        V_VALOR := REPLACE(V_VALOR, CHR(8), '\b');
        V_VALOR := REPLACE(V_VALOR, CHR(9), '\t');
        V_VALOR := REPLACE(V_VALOR, CHR(10), '\n');
        V_VALOR := REPLACE(V_VALOR, CHR(12), '\f');
        V_VALOR := REPLACE(V_VALOR, CHR(13), '\r');

        RETURN '"' || V_VALOR || '"';
    END FN_JSON_STRING;

    /* Rotina interna: valor numerico valido independentemente do NLS da sessao. */
    FUNCTION FN_JSON_NUMBER(P_VALOR IN NUMBER) RETURN VARCHAR2 IS
    BEGIN
        IF P_VALOR IS NULL THEN
            RETURN 'null';
        END IF;

        RETURN TO_CHAR(
            P_VALOR,
            'FM999999990D00',
            'NLS_NUMERIC_CHARACTERS=''.,'''
        );
    END FN_JSON_NUMBER;

    FUNCTION FN_ANIMAL_TO_JSON (
        P_ID             IN T_ANIMAL.ID%TYPE,
        P_NAME           IN T_ANIMAL.NAME%TYPE,
        P_NICKNAME       IN T_ANIMAL.NICKNAME%TYPE,
        P_GENDER         IN T_ANIMAL.GENDER%TYPE,
        P_BIRTH_DATE     IN T_ANIMAL.BIRTH_DATE%TYPE,
        P_RGA            IN T_ANIMAL.RGA%TYPE,
        P_MICROCHIP_CODE IN T_ANIMAL.MICROCHIP_CODE%TYPE,
        P_IS_NEUTERED    IN T_ANIMAL.IS_NEUTERED%TYPE,
        P_WEIGHT         IN T_ANIMAL.WEIGHT%TYPE,
        P_HEIGHT         IN T_ANIMAL.HEIGHT%TYPE,
        P_COLOR          IN T_ANIMAL.COLOR%TYPE,
        P_STATUS         IN T_ANIMAL.STATUS%TYPE,
        P_SPECIES_NAME   IN T_SPECIES.NAME%TYPE,
        P_BREED_NAME     IN T_BREED.NAME%TYPE,
        P_BREED_SIZE     IN T_BREED.PORT%TYPE
    ) RETURN VARCHAR2
    IS
        V_JSON VARCHAR2(32767);

        E_ID_INVALIDO     EXCEPTION;
        E_NOME_INVALIDO   EXCEPTION;
        E_GENERO_INVALIDO EXCEPTION;
    BEGIN
        IF P_ID IS NULL OR P_ID <= 0 THEN
            RAISE E_ID_INVALIDO;
        END IF;

        IF P_NAME IS NULL OR TRIM(P_NAME) IS NULL THEN
            RAISE E_NOME_INVALIDO;
        END IF;

        IF P_GENDER IS NOT NULL
           AND UPPER(P_GENDER) NOT IN ('M', 'F') THEN
            RAISE E_GENERO_INVALIDO;
        END IF;

        V_JSON := '{' ||
            '"id":' || TO_CHAR(P_ID) ||
            ',"nome":' || FN_JSON_STRING(P_NAME) ||
            ',"apelido":' || FN_JSON_STRING(P_NICKNAME) ||
            ',"genero":' || FN_JSON_STRING(P_GENDER) ||
            ',"dataNascimento":' ||
                CASE
                    WHEN P_BIRTH_DATE IS NULL THEN 'null'
                    ELSE FN_JSON_STRING(TO_CHAR(P_BIRTH_DATE, 'YYYY-MM-DD'))
                END ||
            ',"rga":' || FN_JSON_STRING(P_RGA) ||
            ',"microchip":' || FN_JSON_STRING(P_MICROCHIP_CODE) ||
            ',"castrado":' ||
                CASE
                    WHEN P_IS_NEUTERED IS NULL THEN 'null'
                    WHEN UPPER(P_IS_NEUTERED) = 'S' THEN 'true'
                    ELSE 'false'
                END ||
            ',"peso":' || FN_JSON_NUMBER(P_WEIGHT) ||
            ',"altura":' || FN_JSON_NUMBER(P_HEIGHT) ||
            ',"cor":' || FN_JSON_STRING(P_COLOR) ||
            ',"status":' || FN_JSON_STRING(P_STATUS) ||
            ',"especie":' || FN_JSON_STRING(P_SPECIES_NAME) ||
            ',"raca":' || FN_JSON_STRING(P_BREED_NAME) ||
            ',"porte":' || FN_JSON_STRING(P_BREED_SIZE) ||
            '}';

        RETURN V_JSON;

    EXCEPTION
        WHEN E_ID_INVALIDO THEN
            RETURN '{"erro":"ID do animal invalido"}';
        WHEN E_NOME_INVALIDO THEN
            RETURN '{"erro":"Nome do animal obrigatorio"}';
        WHEN E_GENERO_INVALIDO THEN
            RETURN '{"erro":"Genero invalido. Valores permitidos: M ou F"}';
        WHEN VALUE_ERROR THEN
            RETURN '{"erro":"Erro de conversao ou valor invalido durante a geracao do JSON"}';
        WHEN OTHERS THEN
            RETURN '{"erro":"Erro inesperado durante a geracao do JSON"}';
    END FN_ANIMAL_TO_JSON;

    PROCEDURE PR_LISTAR_ANIMAIS_JSON (
        P_SPECIES_NAME IN T_SPECIES.NAME%TYPE DEFAULT NULL
    ) IS
        V_SPECIES_ID T_SPECIES.ID%TYPE;
        V_COUNT      NUMBER := 0;

        E_ESPECIE_NAO_ENCONTRADA EXCEPTION;
        E_NENHUM_ANIMAL          EXCEPTION;
        E_PARAMETRO_INVALIDO     EXCEPTION;
    BEGIN
        /* No Oracle, TRIM de string so com espacos resulta em NULL. */
        IF P_SPECIES_NAME IS NOT NULL
           AND TRIM(P_SPECIES_NAME) IS NULL THEN
            RAISE E_PARAMETRO_INVALIDO;
        END IF;

        IF P_SPECIES_NAME IS NOT NULL THEN
            BEGIN
                SELECT ID
                  INTO V_SPECIES_ID
                  FROM T_SPECIES
                 WHERE UPPER(NAME) = UPPER(TRIM(P_SPECIES_NAME));
            EXCEPTION
                WHEN NO_DATA_FOUND OR TOO_MANY_ROWS THEN
                    RAISE E_ESPECIE_NAO_ENCONTRADA;
            END;
        END IF;

        FOR R IN (
            SELECT A.ID, A.NAME, A.NICKNAME, A.GENDER,
                   A.BIRTH_DATE, A.RGA, A.MICROCHIP_CODE,
                   A.IS_NEUTERED, A.WEIGHT, A.HEIGHT,
                   A.COLOR, A.STATUS,
                   S.NAME AS SPECIES_NAME,
                   B.NAME AS BREED_NAME,
                   B.PORT AS BREED_SIZE
              FROM T_ANIMAL A
              JOIN T_BREED B ON B.ID = A.T_BREED_ID
              JOIN T_SPECIES S ON S.ID = A.T_SPECIES_ID
             WHERE P_SPECIES_NAME IS NULL OR S.ID = V_SPECIES_ID
             ORDER BY A.ID
        ) LOOP
            V_COUNT := V_COUNT + 1;

            DBMS_OUTPUT.PUT_LINE(
                FN_ANIMAL_TO_JSON(
                    R.ID, R.NAME, R.NICKNAME, R.GENDER, R.BIRTH_DATE,
                    R.RGA, R.MICROCHIP_CODE, R.IS_NEUTERED,
                    R.WEIGHT, R.HEIGHT, R.COLOR, R.STATUS,
                    R.SPECIES_NAME, R.BREED_NAME, R.BREED_SIZE
                )
            );
        END LOOP;

        IF V_COUNT = 0 THEN
            RAISE E_NENHUM_ANIMAL;
        END IF;

        DBMS_OUTPUT.PUT_LINE('Total de animais encontrados: ' || V_COUNT);

    EXCEPTION
        WHEN E_PARAMETRO_INVALIDO THEN
            DBMS_OUTPUT.PUT_LINE('ERRO: O nome da especie informado e invalido.');
        WHEN E_ESPECIE_NAO_ENCONTRADA THEN
            DBMS_OUTPUT.PUT_LINE(
                'ERRO: A especie "' || P_SPECIES_NAME || '" nao foi encontrada.'
            );
        WHEN E_NENHUM_ANIMAL THEN
            DBMS_OUTPUT.PUT_LINE(
                'ERRO: Nenhum animal foi encontrado para o filtro informado.'
            );
        WHEN VALUE_ERROR THEN
            DBMS_OUTPUT.PUT_LINE(
                'ERRO: Valor invalido durante o processamento dos dados.'
            );
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE(
                'ERRO INESPERADO: ' || SQLCODE || ' - ' || SQLERRM
            );
    END PR_LISTAR_ANIMAIS_JSON;

END PKG_ANIMAL;
/
