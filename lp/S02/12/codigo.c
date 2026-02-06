#include <stdio.h>
#include <stdlib.h>
#define TAM 4

int main(){
    int *vetor = (int *) malloc(TAM * sizeof(int));
    int *it = vetor;
    int *fim = vetor + TAM;

    do{
        *it = 10;
        it++;
    }while(it < fim);

    it = vetor;

    for(int i=0; i<TAM; i++){
         printf("Valor: %d", vetor[i]);
    }

    free(vetor);

    return 0;
}