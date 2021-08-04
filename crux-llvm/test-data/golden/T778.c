unsigned int addflt(unsigned int a , unsigned int b )
{
  unsigned int ma = a;
  unsigned int mb = b;
  int ea = (int)(a >> 24U) - 128;
  int eb = (int)(b >> 24U) - 128;
  unsigned int delta = ea - eb;

  mb = mb >> delta;
  ma = ma + mb;

  // This if statement seems critical
  if (ma) {
    ea = ea + 1;
  }

  return ((unsigned int) ea);
}

int main() {
  return 0;
}
