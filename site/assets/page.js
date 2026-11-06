// The top bar turns to glass once the page scrolls, as on the home page.
(() => {
  const bar = document.querySelector('.bar');
  const update = () => bar.classList.toggle('scrolled', scrollY > 8);
  addEventListener('scroll', update, { passive: true });
  update();
})();
