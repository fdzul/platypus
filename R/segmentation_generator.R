#' Splits multi-class mask into binary masks.
#' @description Splits multi-class mask into binary masks.
#' @param mask Segmentation mask.
#' @param colormap Class color map. For example \code{\link[platypus]{voc_colormap}}.
#' @export
split_masks_into_binary <- function(mask, colormap) {
  colormap %>% map(~ {
    current_color <- .x
    current_color %>% imap(~ {
      mask[ , , .y, drop = TRUE] == .x
    }) %>% reduce(`+`) %>% `==`(3) %>% `*`(1)
  })
}

#' Reads images from directory.
#' @description Reads images from directory.
#' @import keras
#' @importFrom abind abind
#' @importFrom purrr map reduce
#' @param paths Images directories.
#' @param indices Indices of selected images. If `NULL` all images in `paths` will be selected.
#' @param target_size Images size (height, width). Default to `c(256, 256)`.
#' @param grayscale Boolean, whether to load the image as grayscale.
#' @param scale Scaling factor for images pixel values. Default to `1 / 255`.
#' @param colormap Class color map. For example \code{\link[platypus]{voc_colormap}}.
#' @export
read_images_from_directory <- function(paths, indices = NULL, target_size = c(256, 256),
                                       grayscale = FALSE, scale = 1 / 255, colormap = NULL) {
  indices <- if (is.null(indices)) 1:length(paths) else indices
  map(paths[indices], ~ {
    current_paths <- .x
    current_paths %>% map(~ image_to_array(image_load(.x, grayscale = grayscale, target_size = target_size))) %>%
      reduce(`+`) %>%
      when(!is.null(colormap) ~ split_masks_into_binary(., colormap) %>%
             abind(along = 3), ~ . * scale)
  }) %>%
    abind(along = 4) %>% aperm(c(4, 1, 2, 3))
}

#' Generates images/masks path from selected configuration.
#' @description Generates images/masks path from selected configuration.
#' @importFrom purrr map
#' @importFrom readr read_csv
#' @param path Images directories or configuration file path.
#' @param mode Character. One of `c("dir", "nested_dirs", "config_file")` or `c(1, 2, 3)` correspondingly.
#' @param only_images Should generator read only images (e.g. on train set for predictions).
#' @param subdirs Vector of two characters containing names of subdirectories with images and masks.
#' @param column_sep Character. Configuration file separator.
#' @export
create_images_masks_paths <- function(path, mode, only_images, subdirs = c("images", "masks"), column_sep = ";") {
  if (mode %in% c("dir", 1)) {
    images_paths <- list.files(file.path(path, subdirs[1]), full.names  = TRUE) %>% as.list()
    masks_paths <- if (!only_images) list.files(file.path(path, subdirs[2]), full.names = TRUE) %>% as.list() else NULL
  } else if (mode %in% c("nested_dirs", 2)) {
    nested_dirs <- list.dirs(path, full.names  = TRUE, recursive = FALSE)
    images_paths <- nested_dirs %>% map(~ list.files(file.path(.x, subdirs[1]), full.names  = TRUE))
    masks_paths <- if (!only_images) nested_dirs %>% map(~ list.files(file.path(.x, subdirs[2]), full.names  = TRUE)) else NULL
  } else {
    config_file <- read_csv(path)
    images_paths <- config_file$images %>% as.list()
    masks_paths <- config_file$masks %>% strsplit(column_sep)
  }
  list(images_paths = images_paths, masks_paths = masks_paths)
}

#' Generates batches of data (images and masks). The data will be looped over (in batches).
#' @description Generates batches of data (images and masks). The data will be looped over (in batches).
#' @importFrom purrr map
#' @param path Images and masks directory.
#' @param colormap Class color map. For example \code{\link[platypus]{voc_colormap}}.
#' @param mode Character. One of `c("dir", "nested_dirs", "config_file")`
#' @param only_images Should generator read only images (e.g. on train set for predictions).
#' @param net_h Input layer height. Must be equal to `2^x, x - natural`.
#' @param net_w Input layer width. Must be equal to `2^x, x - natural`.
#' @param grayscale Defines input layer color channels -  `1` if `TRUE`, `3` if `FALSE`.
#' @param scale Scaling factor for images pixel values. Default to `1 / 255`.
#' @param batch_size Batch size.
#' @param shuffle Should data be shuffled.
#' @param subdirs Vector of two characters containing names of subdirectories with images and masks.
#' @param column_sep Character. Configuration file separator.
#' @export
segmentation_generator <- function(path, colormap, mode = "dir", only_images = FALSE, net_h = 256, net_w = 256,
                                   grayscale = FALSE, scale = 1 / 255,
                                   batch_size = 32, shuffle = TRUE, subdirs = c("images", "masks"),
                                   column_sep = ";") {
  target_size <- c(net_h, net_w)
  n_class <- length(colormap)
  segmentation_generator_check(colormap, mode, n_class, only_images, net_h, net_w, grayscale, shuffle)
  config <- create_images_masks_paths(path, mode, only_images, subdirs, column_sep)
  cat(paste0(length(config$images_paths), " images", if (!only_images) " with corresponding masks", " detected!\n"))
  cat(paste0("Set 'steps_per_epoch' to: ", ceiling(length(config$images_paths) / batch_size), "\n"))
  i <- 1
  as_generator.function(function() {
    if (shuffle) {
      indices <- sample(1:length(config$images_paths), size = batch_size)
    } else {
      indices <- c(i:min(i + batch_size - 1, length(config$images_paths)))
      i <<- if (i + batch_size > length(config$images_paths)) 1 else i + length(indices)
    }
    images <- read_images_from_directory(config$images_paths, indices = indices, target_size = c(net_h, net_w),
                                         grayscale = grayscale, scale = scale, colormap = NULL)
    if (!only_images) masks <- read_images_from_directory(config$masks_paths, indices = indices, target_size = c(net_h, net_w),
                                                          grayscale = FALSE, scale = 1 / 255, colormap = colormap)
    if (!only_images) list(images, masks) else list(images)
  })
}
