/* =========================================================
   PACKAGE: PKG_AGENDAMENTO
   Responsabilidade: sumarizacao e auditoria dos agendamentos.
   Depende de T_APPOINTMENT e T_APPOINTMENT_AUDIT.
========================================================= */

CREATE OR REPLACE PACKAGE PKG_AGENDAMENTO AS

    /* Estrutura compartilhada entre a trigger e a rotina de auditoria. */
    TYPE T_DADOS_AUDITORIA IS RECORD (
        APPOINTMENT_ID    T_APPOINTMENT.ID%TYPE,
        APPOINTMENT_TYPE  T_APPOINTMENT.APPOINTMENT_TYPE%TYPE,
        STATUS            T_APPOINTMENT.STATUS%TYPE,
        SCHEDULED_START   T_APPOINTMENT.SCHEDULED_START%TYPE,
        SCHEDULED_END     T_APPOINTMENT.SCHEDULED_END%TYPE,
        PRICE             T_APPOINTMENT.PRICE%TYPE,
        NOTES             T_APPOINTMENT.NOTES%TYPE
    );

    /* Relatorio de totais por APPOINTMENT_TYPE e STATUS. */
    PROCEDURE PR_APPOINTMENT_SUMMARY;

    /* Ponto de entrada reutilizavel para auditoria feita pela trigger. */
    PROCEDURE PR_REGISTRAR_AUDITORIA (
        P_OPERACAO IN VARCHAR2,
        P_ANTERIOR IN T_DADOS_AUDITORIA,
        P_NOVO     IN T_DADOS_AUDITORIA
    );

END PKG_AGENDAMENTO;
/

CREATE OR REPLACE PACKAGE BODY PKG_AGENDAMENTO AS

    PROCEDURE PR_APPOINTMENT_SUMMARY IS
        V_COMBINATION_TOTAL NUMBER(10,2) := 0;
        V_SUBTOTAL          NUMBER(10,2) := 0;
        V_TOTAL_GENERAL     NUMBER(10,2) := 0;
        V_DETAIL_COUNT      NUMBER := 0;

        E_NO_DATA          EXCEPTION;
        E_INVALID_PRICE    EXCEPTION;
        E_INVALID_CATEGORY EXCEPTION;
    BEGIN
        DBMS_OUTPUT.PUT_LINE(
            RPAD('APPOINTMENT_TYPE', 22) ||
            RPAD('STATUS', 18) ||
            'PRICE'
        );
        DBMS_OUTPUT.PUT_LINE(
            RPAD('-', 22, '-') ||
            RPAD('-', 18, '-') ||
            RPAD('-', 12, '-')
        );

        FOR R_TYPE IN (
            SELECT DISTINCT APPOINTMENT_TYPE
              FROM T_APPOINTMENT
             WHERE APPOINTMENT_TYPE IS NOT NULL
             ORDER BY APPOINTMENT_TYPE
        ) LOOP
            IF TRIM(R_TYPE.APPOINTMENT_TYPE) IS NULL THEN
                RAISE E_INVALID_CATEGORY;
            END IF;

            V_SUBTOTAL := 0;

            FOR R_STATUS IN (
                SELECT DISTINCT STATUS
                  FROM T_APPOINTMENT
                 WHERE APPOINTMENT_TYPE = R_TYPE.APPOINTMENT_TYPE
                   AND STATUS IS NOT NULL
                 ORDER BY STATUS
            ) LOOP
                V_COMBINATION_TOTAL := 0;

                FOR R_DETAIL IN (
                    SELECT PRICE
                      FROM T_APPOINTMENT
                     WHERE APPOINTMENT_TYPE = R_TYPE.APPOINTMENT_TYPE
                       AND STATUS = R_STATUS.STATUS
                     ORDER BY ID
                ) LOOP
                    IF R_DETAIL.PRICE IS NULL OR R_DETAIL.PRICE < 0 THEN
                        RAISE E_INVALID_PRICE;
                    END IF;

                    V_COMBINATION_TOTAL :=
                        V_COMBINATION_TOTAL + R_DETAIL.PRICE;

                    V_TOTAL_GENERAL :=
                        V_TOTAL_GENERAL + R_DETAIL.PRICE;

                    V_DETAIL_COUNT := V_DETAIL_COUNT + 1;
                END LOOP;

                DBMS_OUTPUT.PUT_LINE(
                    RPAD(R_TYPE.APPOINTMENT_TYPE, 22) ||
                    RPAD(R_STATUS.STATUS, 18) ||
                    TO_CHAR(V_COMBINATION_TOTAL, 'FM999999990D00',
                            'NLS_NUMERIC_CHARACTERS=''.,''')
                );

                V_SUBTOTAL := V_SUBTOTAL + V_COMBINATION_TOTAL;
            END LOOP;

            DBMS_OUTPUT.PUT_LINE(
                RPAD(R_TYPE.APPOINTMENT_TYPE, 22) ||
                RPAD('NULL', 18) ||
                TO_CHAR(V_SUBTOTAL, 'FM999999990D00',
                        'NLS_NUMERIC_CHARACTERS=''.,''')
            );
            DBMS_OUTPUT.PUT_LINE('');
        END LOOP;

        IF V_DETAIL_COUNT = 0 THEN
            RAISE E_NO_DATA;
        END IF;

        DBMS_OUTPUT.PUT_LINE(
            RPAD('NULL', 22) ||
            RPAD('NULL', 18) ||
            TO_CHAR(V_TOTAL_GENERAL, 'FM999999990D00',
                    'NLS_NUMERIC_CHARACTERS=''.,''')
        );

    EXCEPTION
        WHEN E_NO_DATA THEN
            DBMS_OUTPUT.PUT_LINE(
                'ERRO: Nenhum registro encontrado em T_APPOINTMENT.'
            );
        WHEN E_INVALID_PRICE THEN
            DBMS_OUTPUT.PUT_LINE('ERRO: Foi encontrado PRICE nulo ou negativo.');
        WHEN E_INVALID_CATEGORY THEN
            DBMS_OUTPUT.PUT_LINE(
                'ERRO: APPOINTMENT_TYPE nao pode ser nulo ou vazio.'
            );
        WHEN VALUE_ERROR THEN
            DBMS_OUTPUT.PUT_LINE(
                'ERRO: Falha de conversao ou valor numerico invalido.'
            );
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE(
                'ERRO inesperado: ' || SQLCODE || ' - ' || SQLERRM
            );
    END PR_APPOINTMENT_SUMMARY;

    PROCEDURE PR_REGISTRAR_AUDITORIA (
        P_OPERACAO IN VARCHAR2,
        P_ANTERIOR IN T_DADOS_AUDITORIA,
        P_NOVO     IN T_DADOS_AUDITORIA
    ) IS
        V_APPOINTMENT_ID T_APPOINTMENT.ID%TYPE;
    BEGIN
        IF P_OPERACAO IS NULL
           OR P_OPERACAO NOT IN ('INSERT', 'UPDATE', 'DELETE') THEN
            RAISE_APPLICATION_ERROR(-20001, 'Operacao de auditoria invalida.');
        END IF;

        IF P_OPERACAO = 'DELETE' THEN
            V_APPOINTMENT_ID := P_ANTERIOR.APPOINTMENT_ID;
        ELSE
            V_APPOINTMENT_ID := P_NOVO.APPOINTMENT_ID;
        END IF;

        IF V_APPOINTMENT_ID IS NULL THEN
            RAISE_APPLICATION_ERROR(-20002, 'ID do agendamento obrigatorio.');
        END IF;

        /* Sem COMMIT: o log acompanha a transacao original. */
        INSERT INTO T_APPOINTMENT_AUDIT (
            USER_NAME, OPERATION_TYPE, OPERATION_DATE, APPOINTMENT_ID,
            OLD_APPOINTMENT_TYPE, OLD_STATUS,
            OLD_SCHEDULED_START, OLD_SCHEDULED_END, OLD_PRICE, OLD_NOTES,
            NEW_APPOINTMENT_TYPE, NEW_STATUS,
            NEW_SCHEDULED_START, NEW_SCHEDULED_END, NEW_PRICE, NEW_NOTES
        ) VALUES (
            SYS_CONTEXT('USERENV', 'SESSION_USER'),
            P_OPERACAO,
            SYSTIMESTAMP,
            V_APPOINTMENT_ID,
            P_ANTERIOR.APPOINTMENT_TYPE,
            P_ANTERIOR.STATUS,
            P_ANTERIOR.SCHEDULED_START,
            P_ANTERIOR.SCHEDULED_END,
            P_ANTERIOR.PRICE,
            P_ANTERIOR.NOTES,
            P_NOVO.APPOINTMENT_TYPE,
            P_NOVO.STATUS,
            P_NOVO.SCHEDULED_START,
            P_NOVO.SCHEDULED_END,
            P_NOVO.PRICE,
            P_NOVO.NOTES
        );
    END PR_REGISTRAR_AUDITORIA;

END PKG_AGENDAMENTO;
/
