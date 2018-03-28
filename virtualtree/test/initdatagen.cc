#include <iostream>
#include <iomanip>
#include <fstream>
#include <vector>
#include <algorithm>
#include <random>
#include <cassert>

int main(int argc, char *argv[]) {

  assert(argc == 3);
  
//   auto datanum = std::atoi(argv[1]);
//   auto waynum = std::atoi(argv[2]);
  
//   std::vector<int> data(datanum);
//   std::default_random_engine g_engine_(std::random_device{}());
//   std::uniform_int_distribution<int> distribution(0, 0x7fffffff);
  
// // #pragma omp parallel for
//   for (auto loop = 0; loop < waynum; ++loop) {
//     for (auto i = 0; i < datanum; ++i) {
//       data[i] = distribution(g_engine_);
//     }
//     std::sort(&data[0], &data[datanum], std::less<int>());
//     for (auto i = 0; i < datanum; ++i) {
//       std::cout << std::hex << std::setw(8) << std::setfill('0') << data[i] << std::endl;
//     }
//     // std::cout << std::endl;
//   }
  
  auto datanum_per_way = std::atoi(argv[1]);
  auto way_log         = std::atoi(argv[2]);

  auto sortnum = datanum_per_way * (1 << way_log);
  
  std::vector<int> data(sortnum);
  std::default_random_engine g_engine_(std::random_device{}());
  std::uniform_int_distribution<int> distribution(0, 0x7fffffff);
  
  for (auto i = 0; i < sortnum; ++i) {
    data[i] = distribution(g_engine_);
  }

  for (auto i = 0; i < (1 << way_log); ++i) {
    std::sort(&data[datanum_per_way*i], &data[datanum_per_way*(i+1)], std::less<int>());
  }

  std::ofstream fout("initdata.hex");
  for (auto i = 0; i < sortnum; ++i) {
    // std::cout << std::hex << std::setw(8) << std::setfill('0') << data[i] << std::endl;
    fout << std::hex << std::setw(8) << std::setfill('0') << data[i] << std::endl;
  }
  fout.close();

  std::sort(&data[0], &data[sortnum], std::less<int>());
  // std::cout << std::endl;

  fout.open("answer.txt");
  for (auto i = 0; i < sortnum; ++i) {
    // std::cout << std::hex << std::setw(8) << std::setfill('0') << data[i] << std::endl;
    fout << std::hex << std::setw(8) << std::setfill('0') << data[i] << std::endl;
  }
  fout.close();
  
  return 0;
}
